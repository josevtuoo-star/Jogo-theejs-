#!/usr/bin/env python3
"""
Importa assets CC0 de terceiros (nada é criado do zero) para www/assets:
  - veículos: Kenney "Starter Kit Racing" (CC0)  -> assets/models/vehicle_*.glb (textura embutida)
  - sons: Kenney Starter Kits (CC0) + OpenGameArt (CC0: [kdd] Different Steps, rubberduck 100 CC0 SFX #2 / 75 CC0 breaking,
          kheetor Tree chop, Ylmir Rain loopable, Birds and Wind)           -> assets/audio/*.ogg
Uso: python3 tools/import_external.py <kenney-racing> <kenney-fps> <pasta-oga-extraida>
"""
import json, os, shutil, struct, sys
RACING, FPS, OGA = sys.argv[1:4]
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'www', 'assets')
os.makedirs(ROOT + '/models', exist_ok=True); os.makedirs(ROOT + '/audio', exist_ok=True)

def read_glb(p):
    b = open(p, 'rb').read(); off = 12; js = bn = None
    while off < len(b):
        l, t = struct.unpack('<II', b[off:off + 8]); d = b[off + 8:off + 8 + l]
        if t == 0x4E4F534A: js = json.loads(d)
        elif t == 0x004E4942: bn = bytearray(d)
        off += 8 + l
    return js, bn

def write_glb(js, bn, dst):
    while len(bn) % 4: bn.append(0)
    js['buffers'] = [{'byteLength': len(bn)}]
    j = json.dumps(js, separators=(',', ':')).encode()
    while len(j) % 4: j += b' '
    open(dst, 'wb').write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(bn)) + struct.pack('<II', len(j), 0x4E4F534A) + j + struct.pack('<II', len(bn), 0x004E4942) + bytes(bn))

png = open(os.path.join(RACING, 'models', 'Textures', 'colormap.png'), 'rb').read()
for color in ['green', 'red', 'yellow', 'purple']:
    js, bn = read_glb(os.path.join(RACING, 'models', f'vehicle-truck-{color}.glb'))
    while len(bn) % 4: bn.append(0)
    off = len(bn); bn += png
    js['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(png)})
    js['images'] = [{'bufferView': len(js['bufferViews']) - 1, 'mimeType': 'image/png'}]
    write_glb(js, bn, f'{ROOT}/models/vehicle_{color}.glb')

A = ROOT + '/audio'
def cp(src, name): shutil.copyfile(src, f'{A}/{name}.ogg')
# Kenney (CC0)
for n in ['engine', 'skid', 'impact']: cp(f'{RACING}/audio/{n}.ogg', f'car_{n}')
for n in ['jump_a', 'jump_b', 'jump_c', 'land']: cp(f'{FPS}/sounds/{n}.ogg', n)
# OpenGameArt (CC0)
steps = f'{OGA}/steps'; s100 = f'{OGA}/sfx100'; bfh = f'{OGA}/bfh'
for i, n in enumerate(['leaves01', 'leaves02']): cp(f'{steps}/{n}.ogg', f'step_grass_{i}')
cp(f'{steps}/mud02.ogg', 'step_dirt_0'); cp(f'{s100}/sfx100v2_footstep_wet_01.ogg', 'step_dirt_1')
cp(f'{steps}/gravel.ogg', 'step_gravel_0')
cp(f'{steps}/stone01.ogg', 'step_stone_0'); cp(f'{s100}/sfx100v2_footstep_01.ogg', 'step_stone_1'); cp(f'{s100}/sfx100v2_footstep_02.ogg', 'step_stone_2')
for i, n in enumerate(['wood01', 'wood02', 'wood03']): cp(f'{steps}/{n}.ogg', f'step_wood_{i}')
for i in range(1, 4): cp(f'{s100}/sfx100v2_footstep_wet_0{i}.ogg', f'step_water_{i - 1}')
for i in range(3): cp(f'{s100}/sfx100v2_wood_hit_0{i + 1}.ogg', f'hit_wood_{i}')
cp(f'{bfh}/bfh1_wood_hit_01.ogg', 'hit_wood_3')
cp(f'{bfh}/bfh1_rock_hit_01.ogg', 'hit_rock_0'); cp(f'{s100}/sfx100v2_stones_01.ogg', 'hit_rock_1'); cp(f'{s100}/sfx100v2_stones_02.ogg', 'hit_rock_2')
cp(f'{bfh}/bfh1_rock_breaking_01.ogg', 'break_rock_0'); cp(f'{bfh}/bfh1_rock_breaking_02.ogg', 'break_rock_1')
cp(f'{bfh}/bfh1_wood_breaking_01.ogg', 'break_wood_0'); cp(f'{OGA}/chop-tree-fall.ogg', 'tree_fall')
cp(f'{s100}/sfx100v2_air_02.ogg', 'swing_0'); cp(f'{s100}/sfx100v2_air_03.ogg', 'swing_1')
cp(f'{s100}/sfx100v2_items_01.ogg', 'pickup_0'); cp(f'{s100}/sfx100v2_items_02.ogg', 'pickup_1'); cp(f'{s100}/sfx100v2_switch_01.ogg', 'click')
for i in range(3): cp(f'{s100}/sfx100v2_hit_0{i + 1}.ogg', f'drop_{i}')
cp(f'{s100}/sfx100v2_metal_hit_01.ogg', 'drop_metal'); cp(f'{s100}/sfx100v2_thunder_01.ogg', 'thunder'); cp(f'{s100}/sfx100v2_loop_water_01.ogg', 'amb_water')
cp(f'{OGA}/Birds_and_Wind_-_Ambient_1.ogg', 'amb_day'); cp(f'{OGA}/rain/1.ogg', 'amb_rain')
shutil.copyfile(f'{OGA}/Forest_Ambience.mp3', f'{A}/amb_forest.mp3')
print('ok')
