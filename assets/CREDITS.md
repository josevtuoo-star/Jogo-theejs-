# Créditos dos assets

Todos os arquivos desta pasta são livres para uso (o modelo 3D CC BY 4.0 pede o crédito abaixo). Os sons foram cortados, normalizados e
convertidos para MP3; as texturas foram reduzidas e algumas envelhecidas — veja abaixo.

## Sons (`sfx/`)

| Arquivos | Origem | Licença |
| --- | --- | --- |
| `step_*`, `imp_*` | [Kenney — Impact Sounds](https://kenney.nl/assets/impact-sounds) (footsteps e impacts) | CC0 |
| `door_*`, `creak_*`, `knife_*`, `cloth*`, `belt_handle_*`, `metal_*`, `drop_leather_*`, `chop_*`, `leather_*`, `coins_*`, `metal_pot_*` | [Kenney — RPG Audio](https://kenney.nl/assets/rpg-audio) | CC0 |
| `gun_shot_*` | Walther PPQ 9mm (X_39P) da [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), preparado no projeto [smokeem](https://github.com/mrellcrane/smokeem); tocado mais grave no jogo para soar como .45 | CC0 |
| `gun_reload_*`, `gun_handle_*` | [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) (via smokeem) | CC0 |
| `sg_shot_*` | Benelli Nova calibre 12 (O_21P) da [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), preparado no [smokeem](https://github.com/mrellcrane/smokeem); somado a uma pancada grave sintetizada | CC0 |
| `sg_shell_*`, `sg_rack_*` | "Shell in Chamber" e "Rack" de [Shotgun Reload Sound Effects](https://opengameart.org/content/shotgun-reload-sound-effects) (via smokeem); o "rack" mais agudo é o ferrolho da pistola fechando | CC0 |
| `amb_birds`, `amb_insects` | `mood_sunrise.ogg` / `mood_sunset.ogg` do demo Truck Town, [godot-demo-projects](https://github.com/godotengine/godot-demo-projects) — emendados em loop | MIT (Copyright © 2014-present Godot Engine contributors) |

O tiro também soma uma pancada grave e o eco sintetizados no próprio jogo; vento, fogo, coração,
corvos, respiração e alguns detalhes continuam sintetizados (Web Audio).

## Texturas (`tex/`)

| Arquivos | Origem | Licença |
| --- | --- | --- |
| `ground_grass_*` | [Rocky Terrain 02](https://polyhaven.com/a/rocky_terrain_02) — Amal Kumar, Poly Haven | CC0 |
| `ground_forest_*` | [Forest Ground 01](https://polyhaven.com/a/forrest_ground_01) — Rob Tuytel, Poly Haven | CC0 |
| `ground_dry_*` | [Aerial Rocks 04](https://polyhaven.com/a/aerial_rocks_04) — Rob Tuytel, Poly Haven | CC0 |
| `brick_*` | `brick_diffuse/bump/roughness.jpg` dos exemplos do [three.js](https://github.com/mrdoob/three.js) (escurecido) | MIT (Copyright © 2010-2024 three.js authors) |
| `planks_*` | `hardwood2_diffuse/bump.jpg` dos exemplos do three.js, envelhecido (acinzentado, manchas) | MIT (three.js) |

## Modelo 3D (`../models/`)

| Arquivo | Origem | Licença |
| --- | --- | --- |
| `personagem.glb` | [“enemy”](https://sketchfab.com/3d-models/enemy-15557449d29144c49e02942d87c7316f) por **DJMaesen** ([sketchfab.com/bumstrum](https://sketchfab.com/bumstrum)), com a pistola dele e as animações do arquivo (parado, arma pronta, corrida, andar mirando, agachado mirando, mirando parado — separadas do clipe único "allanims"). No jogo: ossos renomeados no padrão Mixamo, texturas em JPEG, escala em metros | [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/) |
| animações extras dentro de `personagem.glb` | Biblioteca de animações humanas do [Mesh2Motion](https://github.com/Mesh2Motion/mesh2motion-app) (`human-base-animations.glb` e `human-addon-animations.glb`): Walk, Sprint, Walk_Backwards, Strafe_left/right, Crouch_Idle, Crouch_Walk, Walk_Stealth, Jump_Start/air/Land, Roll, Slide, Swim_Fwd, Swim_Idle, Punch_Jab, Punch_Cross, PickUp_Table, Interact, Hit_Chest, Pistol_Reload, Pistol_Shoot, ClimbUp_1m_RM, Climb Ladder, Ladder_Idle, Ledge Hang, Death_A, Idle Hurt, Tired Hunched, Consume, Fixing_Kneeling. Convertidas (retarget) para o esqueleto do personagem, com o deslocamento tirado (o jogo move o corpo) | CC0 |

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
