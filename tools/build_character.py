#!/usr/bin/env python3
"""
Monta o personagem do jogo a partir de assets CC0 existentes (nada é modelado do zero):
  - malha + esqueleto: Quaternius "Universal Base Characters [Standard]"  (CC0)
  - animações: Quaternius "Universal Animation Library 1 e 2 [Standard]"   (CC0)
As animações são reaplicadas ao personagem pelo NOME dos ossos (mesmo esqueleto UE-Mannequin).
Texturas reduzidas para mobile. Saída: www/assets/char/survivor.glb

Uso: python3 tools/build_character.py <pasta com os 3 pacotes> [male|female]
Os pacotes vêm de https://quaternius.com (versão Standard, gratuita, CC0).
"""
import io, json, os, struct, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1]
WHO = sys.argv[2] if len(sys.argv) > 2 else 'male'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'www', 'assets', 'char')
os.makedirs(OUT, exist_ok=True)

def find(*parts):
    for root, _, files in os.walk(SRC):
        for f in files:
            p = os.path.join(root, f)
            if all(x in p for x in parts) and f.endswith(parts[-1]):
                return p
    raise FileNotFoundError(parts)

char_path = find('Base Characters', 'Godot - UE', f'Superhero_{WHO.capitalize()}_FullBody.gltf')
ual1 = find('Universal Animation Library[Standard]', 'Unreal-Godot', 'UAL1_Standard.glb')
ual2 = find('Universal Animation Library 2[Standard]', 'Unreal-Godot', 'UAL2_Standard.glb')

def load_glb(p):
    b = open(p, 'rb').read()
    off = 12; js = None; bn = None
    while off < len(b):
        l, t = struct.unpack('<II', b[off:off + 8])
        d = b[off + 8:off + 8 + l]
        if t == 0x4E4F534A: js = json.loads(d)
        elif t == 0x004E4942: bn = d
        off += 8 + l
    return js, bn

g = json.load(open(char_path))
base_dir = os.path.dirname(char_path)
binb = bytearray(open(os.path.join(base_dir, g['buffers'][0]['uri']), 'rb').read())
def pad():
    while len(binb) % 4: binb.append(0)
pad()
if 'bufferViews' not in g: g['bufferViews'] = []
if 'accessors' not in g: g['accessors'] = []

def add_view(data, target=None):
    pad(); off = len(binb); binb.extend(data); pad()
    v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
    if target: v['target'] = target
    g['bufferViews'].append(v); return len(g['bufferViews']) - 1

# ---------------------------------------------------------------- texturas (reduzidas, embutidas)
def img_bytes(name, size, kind='rgb', roughness=None):
    im = Image.open(os.path.join(base_dir, name))
    if kind == 'orm':   # roughness (cinza) -> ORM (R=ao 1, G=rugosidade, B=metal 0)
        r = im.convert('L').resize((size, size), Image.LANCZOS)
        orm = Image.merge('RGB', (Image.new('L', r.size, 255), r, Image.new('L', r.size, 0)))
        buf = io.BytesIO(); orm.save(buf, 'JPEG', quality=88); return buf.getvalue()
    im = im.convert('RGB').resize((size, size), Image.LANCZOS)
    buf = io.BytesIO(); im.save(buf, 'JPEG', quality=88); return buf.getvalue()

new_images, new_textures = [], []
def add_tex(data):
    vi = add_view(data)
    new_images.append({'bufferView': vi, 'mimeType': 'image/jpeg'})
    new_textures.append({'source': len(new_images) - 1})
    return len(new_textures) - 1

tex_of = {}
for i, t in enumerate(g['textures']):
    tex_of[i] = g['images'][t['source']]['uri']
name_to_mat = {m['name']: m for m in g['materials']}
for m in g['materials']:
    pb = m['pbrMetallicRoughness']
    big = 'Superhero' in m['name']
    sz = 1024 if big else (512 if 'Hair' in m['name'] else 256)
    if 'baseColorTexture' in pb:
        uri = tex_of[pb['baseColorTexture']['index']]
        pb['baseColorTexture'] = {'index': add_tex(img_bytes(uri, sz))}
    if 'normalTexture' in m:
        uri = tex_of[m['normalTexture']['index']]
        fn = os.path.join(base_dir, uri)
        if not os.path.exists(fn): m.pop('normalTexture'); 
        else: m['normalTexture'] = {'index': add_tex(img_bytes(uri, min(sz, 1024))), 'scale': 1.0}
    if 'metallicRoughnessTexture' in pb:
        uri = tex_of[pb['metallicRoughnessTexture']['index']]
        pb['metallicRoughnessTexture'] = {'index': add_tex(img_bytes(uri, sz, 'orm'))}
        pb['metallicFactor'] = 1.0; pb['roughnessFactor'] = 1.0
g['images'] = new_images; g['textures'] = new_textures
g.pop('samplers', None)
for t in g['textures']: pass

# ---------------------------------------------------------------- animações (UAL1 + UAL2) por nome de osso
WANT = {
 1: ['Idle_Loop','Walk_Loop','Jog_Fwd_Loop','Sprint_Loop','Crouch_Idle_Loop','Crouch_Fwd_Loop','Jump_Start','Jump_Loop','Jump_Land',
     'Swim_Fwd_Loop','Swim_Idle_Loop','Death01','Interact','PickUp_Table','Driving_Loop','Hit_Chest','Idle_Torch_Loop','Push_Loop','Roll'],
 2: ['Consume','TreeChopping_Loop','Farm_Harvest','Walk_Carry_Loop','Idle_Lantern_Loop','ClimbUp_1m','Sword_Regular_A','Idle_FoldArms_Loop'],
}
node_idx = {n.get('name'): i for i, n in enumerate(g['nodes'])}
g['animations'] = []
missing = set()
for k, path in ((1, ual1), (2, ual2)):
    js, bn = load_glb(path)
    names = [n.get('name') for n in js['nodes']]
    def read(ai):
        a = js['accessors'][ai]; bv = js['bufferViews'][a['bufferView']]
        comps = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride')
        if stride and stride != comps * 4:
            arr = np.frombuffer(bn, dtype=np.uint8, count=a['count'] * stride, offset=off).reshape(a['count'], stride)[:, :comps * 4].copy().view(np.float32).reshape(a['count'], comps)
        else:
            arr = np.frombuffer(bn, dtype=np.float32, count=a['count'] * comps, offset=off).reshape(a['count'], comps)
        return arr.astype(np.float32), a
    for anim in js['animations']:
        if anim['name'] not in WANT[k]: continue
        chans, samps = [], []
        cache = {}
        for c in anim['channels']:
            nm = names[c['target']['node']]
            if nm not in node_idx: missing.add(nm); continue
            s = anim['samplers'][c['sampler']]
            if c['target']['path'] == 'scale': continue
            key = (s['input'], s['output'])
            if key not in cache:
                t, ta = read(s['input']); v, va = read(s['output'])
                ti = len(g['accessors']); g['accessors'].append({'bufferView': add_view(t.tobytes()), 'componentType': 5126, 'count': len(t), 'type': 'SCALAR', 'min': [float(t.min())], 'max': [float(t.max())]})
                vi = len(g['accessors']); g['accessors'].append({'bufferView': add_view(v.tobytes()), 'componentType': 5126, 'count': len(v), 'type': 'VEC4' if v.shape[1] == 4 else 'VEC3'})
                samps.append({'input': ti, 'output': vi, 'interpolation': 'LINEAR'})
                cache[key] = len(samps) - 1
            chans.append({'sampler': cache[key], 'target': {'node': node_idx[nm], 'path': c['target']['path']}})
        g['animations'].append({'name': anim['name'], 'samplers': samps, 'channels': chans})
print('animações:', [a['name'] for a in g['animations']], 'ossos sem correspondência:', sorted(missing))

# ---------------------------------------------------------------- saída
g['buffers'] = [{'byteLength': len(binb)}]
js = json.dumps(g, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(binb), 0x004E4942) + bytes(binb)
dst = os.path.join(OUT, 'survivor.glb')
open(dst, 'wb').write(out)
print('ok', dst, round(len(out) / 1e6, 2), 'MB')
