# Processa os dados reais para o jogo: res://assets/mapa_real/
import json, numpy as np, math
from PIL import Image
from pyproj import Transformer
from scipy import ndimage
from shapely.geometry import shape, Polygon, LineString
OUT = "/home/user/Jogo-theejs-/assets/mapa_real/"
import os; os.makedirs(OUT, exist_ok=True)
meta = json.load(open("big_meta.json"))
cx, cy, X0, Z0, CELL, W, H = meta["cx"], meta["cy"], meta["X0"], meta["Z0"], meta["cell"], meta["W"], meta["H"]
tr = Transformer.from_crs("EPSG:4326", "EPSG:32724", always_xy=True)
def game(lon, lat):
    x, y = tr.transform(lon, lat)
    return (x - cx, cy - y)  # (leste, sul)
dem = np.load("big_dem.npy").astype(np.float64)
dem = ndimage.gaussian_filter(dem, 1.0)  # tira o "degrau" de 30 m do DEM
pin_i, pin_j = int((0 - X0) / CELL), int((0 - Z0) / CELL)
base = dem[pin_j, pin_i]
hgt = dem - base
print("altura base", base, "faixa", hgt.min(), hgt.max())
xs = X0 + np.arange(W) * CELL
zs = Z0 + np.arange(H) * CELL
GX, GZ = np.meshgrid(xs, zs)
ov = json.load(open("overture_big.json"))
# ---------------------------------------------------------------- estradas
roads = []
for s in ov["segment"]:
    pts = [game(*c) for c in s["geometry"]["coordinates"]]
    paved = s["class"] in ("secondary", "primary", "tertiary") or any((r or {}).get("value") == "paved" for r in (s.get("road_surface") or []))
    name = (s.get("names") or {}).get("primary") if s.get("names") else None
    roads.append({"pts": pts, "asfalto": bool(paved and s["class"] == "secondary"), "nome": name, "largura": 7.0 if s["class"] == "secondary" else 4.0})
# distância de cada célula até a estrada mais próxima (rasteriza linhas finas e usa transformada de distância)
FINE = 2.5
FW, FH = W * 2, H * 2
def raster_lines(sel):
    img = Image.new("L", (FW, FH), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for r in sel:
        p = [((x - X0) / FINE, (z - Z0) / FINE) for x, z in r["pts"]]
        d.line(p, fill=255, width=1)
    return np.array(img) > 0
asf = raster_lines([r for r in roads if r["asfalto"]])
dirt = raster_lines([r for r in roads if not r["asfalto"]])
d_asf = ndimage.distance_transform_edt(~asf) * FINE
d_dirt = ndimage.distance_transform_edt(~dirt) * FINE
# altura das estradas: terreno bem suavizado (rodovia sem degraus), aplicado com rampa lateral
smooth = ndimage.gaussian_filter(hgt, 6.0)
def coarse(a):
    return a[::2, ::2][:H, :W]
da, dd = coarse(d_asf), coarse(d_dirt)
k_asf = 1.0 - np.clip((da - 5.0) / 12.0, 0, 1)
k_dirt = 1.0 - np.clip((dd - 3.0) / 8.0, 0, 1)
smooth2 = ndimage.gaussian_filter(hgt, 3.0)
hgt = hgt * (1 - k_asf) + smooth * k_asf
hgt = hgt * (1 - k_dirt * 0.8) + smooth2 * (k_dirt * 0.8)
# ---------------------------------------------------------------- casas
houses = []
for b in ov["building"]:
    g = shape(b["geometry"])
    if g.geom_type == "MultiPolygon":
        g = max(g.geoms, key=lambda q: q.area)
    pts = [game(*c) for c in g.exterior.coords]
    poly = Polygon(pts)
    if poly.area < 14 or poly.area > 600:
        continue
    r = poly.minimum_rotated_rectangle
    c = list(r.exterior.coords)[:4]
    e0 = (c[1][0] - c[0][0], c[1][1] - c[0][1]); e1 = (c[2][0] - c[1][0], c[2][1] - c[1][1])
    l0, l1 = math.hypot(*e0), math.hypot(*e1)
    ang = math.atan2(e0[1], e0[0]) if l0 >= l1 else math.atan2(e1[1], e1[0])
    cxh, czh = r.centroid.x, r.centroid.y
    if not (-1270 < cxh < 1270 and -1270 < czh < 3318):
        continue
    houses.append({"x": round(cxh, 2), "z": round(czh, 2), "comp": round(max(l0, l1), 2), "larg": round(min(l0, l1), 2), "ang": round(ang, 4)})
print("casas", len(houses))
# piso das casas: chão plano (média) com borda suave
pad = np.zeros_like(hgt); padw = np.zeros_like(hgt)
for hs in houses:
    i, j = int((hs["x"] - X0) / CELL), int((hs["z"] - Z0) / CELL)
    rad = max(hs["comp"], hs["larg"]) * 0.5 + 4.0
    rr = int(rad / CELL) + 2
    j0, j1, i0, i1 = max(j - rr, 0), min(j + rr + 1, H), max(i - rr, 0), min(i + rr + 1, W)
    sub = hgt[j0:j1, i0:i1]
    dist = np.hypot(GX[j0:j1, i0:i1] - hs["x"], GZ[j0:j1, i0:i1] - hs["z"])
    w = 1.0 - np.clip((dist - rad + 4.0) / 5.0, 0, 1)
    level = float(hgt[j, i])
    hs["y"] = round(level, 3)
    pad[j0:j1, i0:i1] += w * level; padw[j0:j1, i0:i1] += w
m = padw > 0
hgt[m] = hgt[m] * (1 - np.clip(padw[m], 0, 1)) + (pad[m] / np.maximum(padw[m], 1e-6)) * np.clip(padw[m], 0, 1)
for hs in houses:
    i, j = int((hs["x"] - X0) / CELL), int((hs["z"] - Z0) / CELL)
    hs["y"] = round(float(hgt[j, i]), 3)
# ---------------------------------------------------------------- água (açudes) e rio seco
b3, b8 = np.load("big_B03.npy"), np.load("big_B08.npy")
ndwi = (b3 - b8) / (b3 + b8 + 1e-6)
wm = ndimage.binary_opening(ndwi > -0.05, iterations=1)
wm = ndimage.binary_dilation(wm, iterations=1)
lab, n = ndimage.label(wm)
ponds = []
for k in range(1, n + 1):
    comp = lab == k
    if comp.sum() < 6:
        continue
    rim = ndimage.binary_dilation(comp, iterations=2) & ~comp
    level = float(np.percentile(hgt[rim], 15)) - 0.4
    dist_in = ndimage.distance_transform_edt(comp) * CELL
    depth = np.clip(dist_in / 12.0, 0, 1) * 2.6 + 0.6
    hgt[comp] = np.minimum(hgt[comp], level - depth[comp])
    jj, ii = np.nonzero(comp)
    ponds.append({"x0": float(xs[ii.min()] - 6), "x1": float(xs[ii.max()] + 6), "z0": float(zs[jj.min()] - 6), "z1": float(zs[jj.max()] + 6), "nivel": round(level, 3),
                  "cx": float(xs[ii].mean()), "cz": float(zs[jj].mean())})
print("açudes", len(ponds), [(round(p["cx"]), round(p["cz"])) for p in ponds])
river = None
for w in ov["water"]:
    if w["geometry"]["type"] == "LineString":
        river = [game(*c) for c in w["geometry"]["coordinates"]]
rv = raster_lines([{"pts": river}]) if river else np.zeros((FH, FW), bool)
d_riv = coarse(ndimage.distance_transform_edt(~rv) * FINE)
bed = np.clip(1.0 - (d_riv - 6.0) / 10.0, 0, 1)
hgt = hgt - bed * 2.2
# ---------------------------------------------------------------- texturas de dados
rgb = np.load("big_rgb.npy")
bright = rgb.mean(0)
b4 = np.load("big_B04.npy")
ndvi = (b8 - b4) / (b8 + b4 + 1e-6)
water_c = ndimage.binary_dilation(wm, iterations=1)
houses_mask = np.zeros_like(hgt, bool)
for hs in houses:
    houses_mask |= (np.hypot(GX - hs["x"], GZ - hs["z"]) < max(hs["comp"], hs["larg"]) * 0.5 + 2.5)
roadish = (da < 6) | (dd < 4)
free = ~(water_c | houses_mask | roadish | (bed > 0.3))
caat = np.clip((112 - bright) / 40.0, 0, 1) * free
green = np.clip((ndvi - 0.42) / 0.15, 0, 1) * (rgb[1] > rgb[0] * 0.85) * free
field = np.clip((bright - 100) / 50.0, 0, 1) * free
veg = np.stack([caat, green, field], -1)
Image.fromarray((veg * 255).astype(np.uint8)).save(OUT + "vegetacao.png")
# máscara fina (2,5 m): R asfalto, G terra (estrada), B água/areia do rio
asf_m = np.clip(1.0 - (d_asf - 3.2) / 1.6, 0, 1)
dirt_m = np.clip(1.0 - (d_dirt - 1.6) / 1.8, 0, 1)
up = lambda a: np.kron(a, np.ones((2, 2)))[:FH, :FW]
wat_m = np.clip(up(water_c.astype(float)) + up(bed) * 0.8, 0, 1)
mask = np.stack([asf_m, dirt_m, wat_m], -1)
Image.fromarray((mask * 255).astype(np.uint8)).save(OUT + "mascara.png")
# cor do satélite (5 m), um pouco mais apagada e sem a névoa azul
col = np.clip(np.moveaxis(rgb, 0, -1), 0, 255) / 255.0
col = np.clip((col - 0.04) * 1.15, 0, 1)
gray = col.mean(-1, keepdims=True)
col = gray + (col - gray) * 0.85
Image.fromarray((col * 255).astype(np.uint8)).save(OUT + "satelite.png")
# alturas em binário (float32, linha por linha de norte para sul)
hgt.astype(np.float32).tofile(OUT + "../../../tmp_altura.bin") if False else hgt.astype(np.float32).tofile("altura.bin")
# lugares
places = [{"nome": "Espaço São José", "x": 480.0, "z": 2500.0, "tipo": "capela"}]
for p in ov["place"]:
    gx, gz = game(*p["geometry"]["coordinates"])
    places.append({"nome": p["names"]["primary"], "x": round(gx, 1), "z": round(gz, 1), "tipo": p.get("basic_category")})
data = {"origem": {"lat": -6.933940, "lon": -38.457590, "altitude": round(float(base), 2)}, "grade": {"x0": X0, "z0": Z0, "celula": CELL, "w": W, "h": H},
        "limites": [-1280, -1280, 1280, 3328], "estradas": [{"pts": [[round(x, 2), round(z, 2)] for x, z in r["pts"]], "asfalto": r["asfalto"], "nome": r["nome"], "largura": r["largura"]} for r in roads],
        "casas": houses, "acudes": ponds, "rio": [[round(x, 1), round(z, 1)] for x, z in river] if river else [], "lugares": places,
        "fontes": "Relevo: Copernicus GLO-30 (ESA). Satélite: Sentinel-2 L2A 19/10/2025 (ESA/Copernicus). Estradas e construções: Overture Maps (OpenStreetMap, ODbL; prédios Google/Microsoft)."}
json.dump(data, open(OUT + "dados.json", "w"), ensure_ascii=False)
print("ok", hgt.min(), hgt.max())
