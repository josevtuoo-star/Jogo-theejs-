# Créditos e licenças

## Código
Todo o código do motor (`www/engine`), do jogo (`www/game`), das ferramentas (`tools`) e do wrapper Android (`android`) foi escrito para este projeto.

## Assets de terceiros

### Poly Haven — licença CC0 (domínio público)
Baixados por `tools/fetch_assets.py` a partir de <https://polyhaven.com> e redimensionados/empacotados em `.glb`/`.jpg`/`.webp`.
Não é exigida atribuição, mas ela é feita aqui com agradecimento aos artistas.

**Texturas:** `leafy_grass`, `forest_ground_04`, `brown_mud_dry`, `rocky_terrain`, `coast_sand_01`, `gravel_road`, `asphalt_04`, `white_plaster_02`, `yellow_plaster`, `weathered_brown_planks`, `red_brick_03`, `concrete_wall_007`, `clay_roof_tiles_02`, `rusty_corrugated_iron`, `pine_bark`, `old_wooden_floor_01`, `dark_planks`, `metal_plate_02`, `grey_roof_tiles`.

**Modelos:** `wooden_axe` (machado), `picke_dirty_01` (picareta), `dry_branches_medium_01`, `stone_01`, `life_jacket`, `cement_bag`, `compost_bag_02`, `trashbag`, `signal_flashlight`, `russian_food_cans_01`, `long_life_food`, `medical_box`, `metal_jerrycan`, `plastic_bottle_gallon`, `old_gas_mask`, `medical_tape`, `can_rusted`, `rubber_boots`, `fishermans_hat`, `binoculars`, `wooden_crate_01`, `old_military_crate`, `barrel_03`, `metal_trash_can`, `cardboard_box_01`, `old_tyre`, `fire_hydrant`, `utility_box_01`, `street_lamp_01`, `tree_stump_01`, `dead_tree_trunk`, `rock_07`, `rock_09`, `shrub_02`, `fern_02`, `wooden_picnic_table`, `painted_wooden_bench`, `propane_tank`.

### Quaternius — CC0
<https://quaternius.com> — **Universal Base Characters** (malha e esqueleto do personagem) e **Universal Animation Library 1 e 2** (27 animações usadas: parado, andar, trotar, correr, agachar, pular, nadar, dirigir, consumir, interagir, pegar, morte…). Montados por `tools/build_character.py`.

### Kenney — CC0
<https://kenney.nl> — **Starter Kit Racing** (os 4 caminhões usados como carros e os sons de motor, derrapagem e impacto) e **Starter Kit FPS** (sons de pulo e aterrissagem).

### OpenGameArt — CC0 (sons)
<https://opengameart.org> — passos: **[kdd] Different Steps**; **rubberduck — 100 CC0 SFX #2** e **75 CC0 breaking/falling/hit SFX** (madeira, pedra, trovão, itens, água); **kheetor — Tree chop and fall**; **Ylmir — Rain loopable**; **Birds and Wind (ambient)**; **Forest Ambience**.

### Gerado proceduralmente (sem licença de terceiros)
Árvores e grama (instanciadas a partir de geradores), céu, nuvens, água, edifícios e estradas do mundo. Nenhum personagem, carro, ferramenta ou som é criado do zero: todos vêm dos pacotes CC0 acima.

## Ferramentas
Pillow (processamento de imagens, licença HPND), Gradle/Android Gradle Plugin (Apache-2.0), Playwright (testes visuais, Apache-2.0).
