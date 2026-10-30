# Créditos dos assets

Todos os arquivos desta pasta são livres para uso. Os sons foram cortados, normalizados e
convertidos para MP3; as texturas foram reduzidas e algumas envelhecidas — veja abaixo.

## Sons (`sfx/`)

| Arquivos | Origem | Licença |
| --- | --- | --- |
| `step_*`, `imp_*` | [Kenney — Impact Sounds](https://kenney.nl/assets/impact-sounds) (footsteps e impacts) | CC0 |
| `door_*`, `creak_*`, `knife_*`, `cloth*`, `belt_handle_*`, `metal_*`, `drop_leather_*`, `chop_*`, `leather_*`, `coins_*`, `metal_pot_*` | [Kenney — RPG Audio](https://kenney.nl/assets/rpg-audio) | CC0 |
| `gun_shot_*` | Walther PPQ 9mm (X_39P) da [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), preparado no projeto [smokeem](https://github.com/mrellcrane/smokeem); tocado mais grave no jogo para soar como .357 | CC0 |
| `gun_reload_*`, `gun_handle_*` | [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) (via smokeem) | CC0 |
| `sg_shot_*` | Benelli Nova calibre 12 (O_21P) da [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), preparado no [smokeem](https://github.com/mrellcrane/smokeem); somado a uma pancada grave sintetizada | CC0 |
| `sg_shell_*`, `sg_rack_*` | "Shell in Chamber" e "Rack" de [Shotgun Reload Sound Effects](https://opengameart.org/content/shotgun-reload-sound-effects) (via smokeem) | CC0 |
| `amb_birds`, `amb_insects` | `mood_sunrise.ogg` / `mood_sunset.ogg` do demo Truck Town, [godot-demo-projects](https://github.com/godotengine/godot-demo-projects) — emendados em loop | MIT (Copyright © 2014-present Godot Engine contributors) |

O tiro também soma uma pancada grave e o eco sintetizados no próprio jogo; a corda e o virote da
besta, o taco cortando o ar, vento, fogo, coração, corvos, respiração e alguns detalhes continuam
sintetizados (Web Audio).

## Texturas (`tex/`)

| Arquivos | Origem | Licença |
| --- | --- | --- |
| `ground_grass_*` | [Rocky Terrain 02](https://polyhaven.com/a/rocky_terrain_02) — Amal Kumar, Poly Haven | CC0 |
| `ground_forest_*` | [Forest Ground 01](https://polyhaven.com/a/forrest_ground_01) — Rob Tuytel, Poly Haven | CC0 |
| `ground_dry_*` | [Aerial Rocks 04](https://polyhaven.com/a/aerial_rocks_04) — Rob Tuytel, Poly Haven | CC0 |
| `brick_*` | `brick_diffuse/bump/roughness.jpg` dos exemplos do [three.js](https://github.com/mrdoob/three.js) (escurecido) | MIT (Copyright © 2010-2024 three.js authors) |
| `planks_*` | `hardwood2_diffuse/bump.jpg` dos exemplos do three.js, envelhecido (acinzentado, manchas) | MIT (three.js) |

## Animações (`anim/`)

| Arquivos | Origem | Licença |
| --- | --- | --- |
| `walk`, `jog`, `run`, `crouch`, `sneak`, `zombie` | Captura de movimento da [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu/) — sujeitos/tomadas 08_01 (andar), 02_03 (trotar), 09_11 (correr), 136_09 (agachado), 77_29 (andar furtivo) e 104_41 (andar de zumbi), na conversão BVH de Bruce Hahne (cgspeed) via [Shriinivas/cmubvh](https://github.com/Shriinivas/cmubvh). Cortados num ciclo de passada (pisada a pisada), adaptados ao esqueleto do personagem, reamostrados em 48 poses e com a altura do quadril corrigida para o pé tocar o chão | Uso livre — "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217." |

## Personagem (`../models/sobrevivente.glb`)

| Arquivo | Origem | Licença |
| --- | --- | --- |
| `sobrevivente.glb` | “Male 15” por elbolilloduro, com o esqueleto humano do [Mesh2Motion](https://github.com/Mesh2Motion/mesh2motion-app) (`static/models-variation/human/male_15.glb`). Suavizado para o jogo (subdivisão com triângulos curvos, dois níveis), mantendo textura e pesos de pele | CC0 |

## Céu (`env/`)

| Arquivo | Origem | Licença |
| --- | --- | --- |
| `forest_slope_1k.hdr` | [Forest Slope](https://polyhaven.com/a/forest_slope) — Poly Haven (via [pmndrs/drei-assets](https://github.com/pmndrs/drei-assets)); no jogo, menos saturado e mais quente | CC0 |

---

Licença MIT (godot-demo-projects e three.js):

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
