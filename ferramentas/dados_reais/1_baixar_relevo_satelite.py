import rasterio, numpy as np, json
from rasterio.windows import from_bounds
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from pyproj import Transformer
from PIL import Image
lat, lon = -6.933940, -38.457590
tr = Transformer.from_crs("EPSG:4326", "EPSG:32724", always_xy=True)
cx, cy = tr.transform(lon, lat)
# mapa: x (leste) -1280..1280, z (sul) -1280..3328 ; margem 200 m
X0, X1, Z0, Z1 = -1480, 1480, -1480, 3528
CELL = 5.0
W = int((X1 - X0) / CELL); Hh = int((Z1 - Z0) / CELL)
dst_tf = from_origin(cx + X0, cy - Z0, CELL, CELL)   # canto noroeste
dst_crs = "EPSG:32724"
def warp(url, band=1, res=Resampling.cubic, scale=None, dtype=np.float32):
    out = np.zeros((Hh, W), dtype=np.float32)
    with rasterio.open(url) as src:
        reproject(rasterio.band(src, band), out, dst_transform=dst_tf, dst_crs=dst_crs, resampling=res)
    return out
dem = warp("https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_S07_00_W039_00_DEM/Copernicus_DSM_COG_10_S07_00_W039_00_DEM.tif")
print("dem", dem.shape, dem.min(), dem.max())
np.save("big_dem.npy", dem)
base = "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/24/M/WT/2025/10/S2B_24MWT_20251019_0_L2A/"
rgb = [warp(base + "TCI.tif", b, Resampling.lanczos) for b in (1, 2, 3)]
np.save("big_rgb.npy", np.stack(rgb))
for b in ["B03", "B04", "B08", "B11"]:
    np.save("big_%s.npy" % b, warp(base + b + ".tif", 1, Resampling.bilinear))
json.dump({"cx": cx, "cy": cy, "X0": X0, "Z0": Z0, "cell": CELL, "W": W, "H": Hh}, open("big_meta.json", "w"))
Image.fromarray(np.clip(np.stack(rgb, -1), 0, 255).astype(np.uint8)).save("big_rgb.png")
print("ok", W, Hh)
