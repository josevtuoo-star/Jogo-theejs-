# Créditos e licenças

## Código
Todo o código do motor (`www/engine`), do jogo (`www/game`), das ferramentas (`tools`) e do wrapper Android (`android`) foi escrito para este projeto.

## Assets de terceiros

### Poly Haven — licença CC0 (domínio público)
Baixados por `tools/fetch_assets.py` a partir de <https://polyhaven.com> e redimensionados/empacotados em `.glb`/`.jpg`/`.webp`.
Não é exigida atribuição, mas ela é feita aqui com agradecimento aos artistas.

**Texturas:** `leafy_grass`, `forest_ground_04`, `brown_mud_dry`, `rocky_terrain`, `coast_sand_01`, `gravel_road`, `asphalt_04`, `white_plaster_02`, `yellow_plaster`, `weathered_brown_planks`, `red_brick_03`, `concrete_wall_007`, `clay_roof_tiles_02`, `rusty_corrugated_iron`, `pine_bark`, `old_wooden_floor_01`, `dark_planks`, `metal_plate_02`, `grey_roof_tiles`.

**Modelos:** `bolt_action_rifle_7_62`, `service_pistol`, `hatchet`, `machete`, `crowbar_01`, `stick_grenade`, `signal_flashlight`, `russian_food_cans_01`, `long_life_food`, `medical_box`, `metal_jerrycan`, `plastic_bottle_gallon`, `ammo_box`, `old_gas_mask`, `medical_tape`, `can_rusted`, `rubber_boots`, `fishermans_hat`, `binoculars`, `wooden_crate_01`, `old_military_crate`, `barrel_03`, `metal_trash_can`, `cardboard_box_01`, `old_tyre`, `fire_hydrant`, `utility_box_01`, `street_lamp_01`, `tree_stump_01`, `dead_tree_trunk`, `rock_07`, `rock_09`, `stone_01`, `boulder_01`, `shrub_02`, `shrub_04`, `fern_02`, `grass_medium_02`, `nettle_plant`, `wooden_picnic_table`, `painted_wooden_bench`, `propane_tank`.

### Personagem provisório — `Soldier.glb` (Mixamo "Vanguard")
Vem de `three.js/examples/models/gltf` (código do three.js sob MIT). O **modelo e as animações são do Mixamo/Adobe**, cujos termos permitem uso em projetos pessoais e comerciais, mas **não** a redistribuição do arquivo isoladamente. Por isso:
- ele está incluído apenas como **placeholder de desenvolvimento**;
- **antes de publicar o repositório/APK publicamente, troque por um personagem CC0** (por exemplo, da Quaternius) ou baixe o seu próprio no Mixamo.

### Gerado proceduralmente (sem licença de terceiros)
Árvores, grama, céu, nuvens, água, edifícios, estradas, carros, mochilas, capacete, partículas, decalques e **todos os sons** (síntese WebAudio).

## Ferramentas
Pillow (processamento de imagens, licença HPND), Gradle/Android Gradle Plugin (Apache-2.0), Playwright (testes visuais, Apache-2.0).
