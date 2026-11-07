#!/usr/bin/env python3
"""
Baixa assets CC0 (Poly Haven) e o personagem de exemplo do three.js, otimiza
para mobile (texturas redimensionadas, GLB único) e grava em www/assets.

Uso:  python3 tools/fetch_assets.py [--force]
Requer: Pillow.   Licenças: ver CREDITS.md
"""
import io, json, os, struct, sys, urllib.request, concurrent.futures as cf
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'www', 'assets')
CACHE = os.environ.get('ASSET_CACHE', '/tmp/ph_cache')
UA = {'User-Agent': 'Mozilla/5.0 jogo-assets-fetch'}
FORCE = '--force' in sys.argv
os.makedirs(CACHE, exist_ok=True)


def http(url):
    key = os.path.join(CACHE, url.replace('://', '_').replace('/', '_'))
    if os.path.exists(key):
        return open(key, 'rb').read()
    for _ in range(4):
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()
            open(key, 'wb').write(data)
            return data
        except Exception as e:
            err = e
    raise err


def api(path):
    return json.loads(http('https://api.polyhaven.com/' + path))


# ---------------------------------------------------------------- texturas
# nome PH -> (arquivo de saída, tamanho albedo, tamanho normal)
TEXTURES = {
    # terreno (texture array)
    'leafy_grass': ('t_grass', 1024), 'forest_ground_04': ('t_forest', 1024),
    'brown_mud_dry': ('t_dirt', 1024), 'rocky_terrain': ('t_rock', 1024),
    'coast_sand_01': ('t_sand', 512), 'gravel_road': ('t_gravel', 512),
    'asphalt_04': ('t_asphalt', 512),
    # construções / materiais (texture array)
    'white_plaster_02': ('m_plaster', 512), 'yellow_plaster': ('m_plaster_y', 512),
    'weathered_brown_planks': ('m_planks', 512), 'red_brick_03': ('m_brick', 512),
    'concrete_wall_007': ('m_concrete', 512), 'clay_roof_tiles_02': ('m_roof', 512),
    'rusty_corrugated_iron': ('m_iron', 512), 'pine_bark': ('m_bark', 512),
    'old_wooden_floor_01': ('m_floor', 512), 'dark_planks': ('m_darkwood', 512),
    'metal_plate_02': ('m_metal', 512), 'grey_roof_tiles': ('m_roof_grey', 512),
}


def fetch_texture(ph, out, size):
    d = api('files/' + ph)
    def pick(key):
        k = d.get(key)
        if not k: return None
        r = k.get('1k') or k.get('2k')
        return http(r['jpg']['url'])
    diff = Image.open(io.BytesIO(pick('Diffuse'))).convert('RGB').resize((size, size), Image.LANCZOS)
    diff.save(f'{ROOT}/tex/{out}_d.jpg', quality=85, optimize=True)
    nor = Image.open(io.BytesIO(pick('nor_gl'))).convert('RGB')
    nsize = min(size, 512)
    nor = nor.resize((nsize, nsize), Image.LANCZOS)
    rough = pick('Rough')
    if rough:
        r = Image.open(io.BytesIO(rough)).convert('L').resize((nsize, nsize), Image.LANCZOS)
    else:
        r = Image.new('L', (nsize, nsize), 200)
    nor.putalpha(r)  # normal.rgb + rugosidade no alfa
    nor.save(f'{ROOT}/tex/{out}_n.webp', quality=90, method=6)
    return out


# ----------------------------------------------------------------- modelos
# nome PH -> tamanho máx. das texturas
MODELS = {
    'bolt_action_rifle_7_62': 1024, 'service_pistol': 1024, 'hatchet': 512, 'machete': 512,
    'crowbar_01': 512, 'stick_grenade': 512, 'signal_flashlight': 512,
    'russian_food_cans_01': 512, 'long_life_food': 512, 'medical_box': 512,
    'metal_jerrycan': 512, 'plastic_bottle_gallon': 512, 'ammo_box': 512,
    'old_gas_mask': 512, 'medical_tape': 512, 'can_rusted': 512, 'rubber_boots': 512,
    'fishermans_hat': 512, 'binoculars': 512,
    'wooden_crate_01': 512, 'old_military_crate': 512, 'barrel_03': 512,
    'metal_trash_can': 512, 'cardboard_box_01': 512, 'old_tyre': 512,
    'fire_hydrant': 512, 'utility_box_01': 512, 'street_lamp_01': 512,
    'tree_stump_01': 512, 'dead_tree_trunk': 512, 'rock_07': 512, 'rock_09': 512,
    'stone_01': 512, 'boulder_01': 512, 'shrub_02': 512, 'shrub_04': 512,
    'fern_02': 512, 'grass_medium_02': 512, 'nettle_plant': 512,
    'wooden_picnic_table': 512, 'painted_wooden_bench': 512, 'propane_tank': 512,
}


def pad4(b, fill=b'\0'):
    return b + fill * ((4 - len(b) % 4) % 4)


def fetch_model(name, maxtex):
    d = api('files/' + name)
    g = d['gltf']['1k']['gltf']
    gltf = json.loads(http(g['url']))
    inc = g['include']
    # buffers (assume 1 buffer)
    assert len(gltf['buffers']) == 1, name
    binblob = http(inc[gltf['buffers'][0]['uri']]['url'])
    bin_out = bytearray(binblob)
    while len(bin_out) % 4: bin_out.append(0)
    views = gltf['bufferViews']
    images = gltf.get('images', [])
    # imagens com alfa -> webp; resto jpeg
    alpha_imgs = set()
    for m in gltf.get('materials', []):
        if m.get('alphaMode') in ('MASK', 'BLEND'):
            t = m.get('pbrMetallicRoughness', {}).get('baseColorTexture')
            if t:
                alpha_imgs.add(gltf['textures'][t['index']]['source'])
    for i, im in enumerate(images):
        raw = http(inc[im['uri']]['url'])
        img = Image.open(io.BytesIO(raw))
        w, h = img.size
        s = min(maxtex, max(w, h))
        if (w, h) != (s, s) and max(w, h) > s:
            img = img.resize((max(1, w * s // max(w, h)), max(1, h * s // max(w, h))), Image.LANCZOS)
        buf = io.BytesIO()
        if i in alpha_imgs:
            img.convert('RGBA').save(buf, 'WEBP', quality=88, method=6)
            mime = 'image/webp'
        else:
            img.convert('RGB').save(buf, 'JPEG', quality=84, optimize=True)
            mime = 'image/jpeg'
        data = buf.getvalue()
        off = len(bin_out)
        bin_out += pad4(data)
        views.append({'buffer': 0, 'byteOffset': off, 'byteLength': len(data)})
        im.pop('uri', None)
        im['bufferView'] = len(views) - 1
        im['mimeType'] = mime
    gltf['buffers'] = [{'byteLength': len(bin_out)}]
    js = pad4(json.dumps(gltf, separators=(',', ':')).encode(), b' ')
    total = 12 + 8 + len(js) + 8 + len(bin_out)
    out = struct.pack('<III', 0x46546C67, 2, total)
    out += struct.pack('<II', len(js), 0x4E4F534A) + js
    out += struct.pack('<II', len(bin_out), 0x004E4942) + bytes(bin_out)
    open(f'{ROOT}/models/{name}.glb', 'wb').write(out)
    return name, len(out)


def main():
    os.makedirs(ROOT + '/tex', exist_ok=True)
    os.makedirs(ROOT + '/models', exist_ok=True)
    with cf.ThreadPoolExecutor(6) as ex:
        jobs = []
        for ph, (out, sz) in TEXTURES.items():
            if FORCE or not os.path.exists(f'{ROOT}/tex/{out}_d.jpg'):
                jobs.append(ex.submit(fetch_texture, ph, out, sz))
        for n, sz in MODELS.items():
            if FORCE or not os.path.exists(f'{ROOT}/models/{n}.glb'):
                jobs.append(ex.submit(fetch_model, n, sz))
        for j in cf.as_completed(jobs):
            try:
                print('ok ', j.result())
            except Exception as e:
                print('ERR', e)
    sol = ROOT + '/models/soldier.glb'
    if FORCE or not os.path.exists(sol):
        url = 'https://raw.githubusercontent.com/mrdoob/three.js/r170/examples/models/gltf/Soldier.glb'
        open(sol, 'wb').write(http(url))
        print('ok  soldier.glb')


if __name__ == '__main__':
    main()
