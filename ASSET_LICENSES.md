# Procedência e licenças dos assets

Regra do projeto: cada recurso tem a licença verificada **por arquivo** na fonte original antes de entrar no repositório. Recursos sem licença identificável, extraídos de jogos comerciais ou com restrição incompatível com o uso pretendido não são aceitos. Como este repositório é **público**, recursos cuja licença proíbe redistribuir os arquivos brutos também ficam de fora.

Todos os assets de terceiros em uso são **CC0 1.0** (domínio público): uso comercial permitido, sem atribuição obrigatória. O personagem jogável é do dono do projeto. Mesmo assim, os autores estão creditados abaixo e em `SOURCE.txt` / `LICENSE_*.txt` dentro de cada pasta.

## Personagem e animações

| Recurso | Autor | Origem | Licença verificada | Uso no jogo |
|---|---|---|---|---|
| Sobrevivente (`assets/characters/survivor/Sobrevivente.fbx`): malha com gorro, jaqueta, calça cargo, botas e luvas, esqueleto de 65 ossos (convenção Mixamo) | Dono do projeto | enviado pelo dono do projeto em 02/11/2026 para substituir o personagem | uso autorizado pelo dono do projeto | personagem jogável; ossos renomeados para os nomes do jogo e animações retargetadas por `tools/retarget_animations.gd` e `tools/build_survivor.gd` |
| Universal Animation Library (Standard, FBX Unreal) | Quaternius | https://opengameart.org/content/universal-animation-library (também em quaternius.itch.io) | CC0 1.0 (página do OpenGameArt e `License.txt` no pacote) | 19 animações retargetadas: parado, andar, trotar, correr, agachado, salto, queda, aterrissagem, socos, ferimentos, interagir, pegar, empurrar, morte, postura com arma (Sword_Idle), golpe de picareta (Sword_Attack, só o primeiro golpe) |
| Universal Animation Library 2 (Standard, GLB) | Quaternius | https://opengameart.org/content/universal-animation-library-2 | CC0 1.0 (página do OpenGameArt) | 14 animações: gancho e sua recuperação (o quadro final é a guarda de defesa), impacto na guarda (Sword_Block), recuo, levantar, consumir, abrir baú, andar carregando, golpes de arma rápido e amplo (Sword_Regular_A/B), corte de árvore (um ciclo do TreeChopping) e os zumbis (Zombie_Idle, Zombie_Walk_Fwd, Zombie_Scratch) |

Os pacotes de animação originais ficam em `assets/_source/` (fora do Git e do APK). `tools/retarget_animations.gd` gera `resources/animations/survivor_body.res` (retarget por delta no espaço do mundo com alinhamento de poses, pois o personagem está em T, + medição de passada e quadros de contato). `tools/build_survivor.gd` monta o personagem (materiais PBR por superfície, cabeça separada para a primeira pessoa) e o ragdoll.

## Sons (OpenGameArt, todos CC0 1.0)

Licença conferida no campo "License(s)" da página de cada pacote e nos arquivos de licença dentro dos pacotes (Kenney: `license.txt`; Corsica_S: `readme.txt`). Convertidos para OGG mono com volume normalizado por `tools/prepare_audio.py`; origem de cada arquivo em `assets/audio/SOURCES.md`.

| Pacote | Autor | Página | Uso |
|---|---|---|---|
| Fantozzi's Footsteps (Grass/Sand & Stone) | Fantozzi | https://opengameart.org/content/fantozzis-footsteps-grasssand-stone | passos na pedra |
| 50 RPG sound effects | Kenney | https://opengameart.org/content/50-rpg-sound-effects | passos na grama e calcanhar abafado do passo na terra, roupa, interruptor, couro |
| 42 Snow and Gravel Footsteps | Corsica_S (extração: qubodup) | https://opengameart.org/content/42-snow-and-gravel-footsteps | passos no gelo |
| 37 hits/punches | Independent.nu | https://opengameart.org/content/37-hitspunches | soco acertando o corpo |
| 75 CC0 breaking/falling/hit sfx | rubberduck | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | impactos em madeira, metal e genéricos, objetos caindo, corpo caindo, defesa; machado na árvore, árvore rachando, picareta na rocha, rocha quebrando e pedras caindo |
| Metal Impact Sounds | BMacZero | https://opengameart.org/content/metal-impact-sounds | metal tilintando, golpe na parede |
| Swishes Sound Pack | artisticdude | https://opengameart.org/content/swishes-sound-pack | braço cortando o ar |
| 15 vocal male strain/hurt/pain/jump sounds | qubodup | https://opengameart.org/content/15-vocal-male-strainhurtpainjump-sounds | esforço, dor, morte; gemidos, ataque e morte dos zumbis (a mesma voz mais grave, rouca e abafada por `tools/prepare_audio.py`) |
| Jump Landing | Macro | https://opengameart.org/content/jump-landing | aterrissagem |
| Fire Crackling | AntumDeluge | https://opengameart.org/content/fire-crackling | fogueira |
| 20 rustles (dry leaves) | qubodup | https://opengameart.org/content/20-rustles-dry-leaves | folhas secas sob o pé (camada do passo no chão de floresta) |
| Breathing tired | mikeask | https://opengameart.org/content/breathing-tired | respiração cansada depois de correr (separada em três respirações avulsas) |

## Cenário (Poly Haven, CC0 1.0 — https://polyhaven.com/license)

| Recurso | Autores | Uso |
|---|---|---|
| Forest Floor (textura) | eye-candy.xyz | chão de floresta (terreno) |
| Leafy Grass (textura) | Charlotte Baglioni | grama da clareira |
| Brown Mud Leaves 01 (textura) | Rob Tuytel | estrada de terra e acampamento |
| Pine Sapling Small (texturas da casca) | Rob Tuytel, Rico Cilliers | troncos das árvores |
| Fir Sapling Medium (modelo, só como fonte) | Rob Tuytel, Rico Cilliers | renderizado por `tools/bake_tree_impostors.gd` no atlas `resources/textures/trees/fir_cards.png` (impostores das árvores); o modelo de 2,3 M polígonos não vai para o jogo |
| Wooden Military Crate | Prabhjinder Singh | caixote |
| Old Military Crate | Jack Mava | caixote |
| Metal Jerrycan Green | Ulan Cabanilla | galão |
| Russian Food Cans 01 | Kosan Aziz | latas de comida |
| Can Rusted | Rahul Chaudhary | lata enferrujada |
| Old Tyre | MP | pneus |
| Barrel 02 | Jorge Camacho | tambores |
| Wooden Barrels 01 | James Ray Cock | barris de madeira |
| Concrete Road Barrier 02 | Amal Kumar | barreiras do posto |
| Utility Box 01 | James Ray Cock | caixa elétrica |
| Stone Fire Pit | Sebastian Platen | fogueira |
| Tree Stump 01 / Dead Tree Trunk | Rob Tuytel | tocos e tronco caído |
| Rock Moss Set 01 | Kless Gyzen | pedras com musgo |
| Boulder 01 | Rico Cilliers | rochas |
| Shrub 03 | Rico Cilliers | arbustos |
| Fern 02 | Rob Tuytel, Rico Cilliers | samambaias |
| Crowbar 01 | Alexander Otterbeck | pé de cabra |
| Machete / Wooden Axe | Ulan Cabanilla | facão e machado |
| Baseball Bat | Enrique Martín | taco com pregos (etapa 7) |
| Wooden Axe 02 | Ulan Cabanilla | machado de bombeiro (cabeça repintada de vermelho) |
| Covered Car | MP | carro coberto por lona nas estradas |
| Rusted Wheel Rim 01 | John Hutcheson | rodas soltas na estrada |
| Vintage Suitcase | Maximilian Schuster | malas abandonadas |
| Trashbag | Benny Weimer | sacos de lixo |
| Plastic Jerrycan | Ulan Cabanilla | galões |
| ~~Rock Face 01~~ | Dario Barresi | removido na etapa 9 (fatia de penhasco com laterais retas; nas encostas ficava flutuando). Substituído por rochedos procedurais |
| Dry Branches Medium 01 | Rico Cilliers | galhos secos no chão da mata |
| Rusty Painted Metal (textura) | Amal Kumar | escorridos da pintura das carcaças |
| Rust Coarse 01 (textura) | Dimitrios Savva, Rico Cilliers | ferrugem das carcaças e dos pregos |
| Road Damaged (textura) | Dimitrios Savva | asfalto velho das rodovias |
| Mossy Rock (textura) | Rob Tuytel | rocha dos barrancos e, sem o verde do musgo, das cavernas |
| Cliff Side (textura) | James Ray Cock, Jenelle van Heerden, Dario Barresi | estratos alaranjados da rocha das cavernas; estalagmites, estalactites e minérios |
| Brown Mud Rocks 01 (textura) | Rob Tuytel | chão de cascalho das galerias |
| Weathered Planks (textura) | Dario Barresi, Dimitrios Savva | tábuas (item), casas de madeira, portas e janelas tapadas |
| Snow 02 (textura) | Rob Tuytel | chão do bioma de neve e neve nas encostas |
| Dry Ground Rocks (textura) | Rob Tuytel | chão do bioma seco |
| Forest Leaves 02 (textura) | Rob Tuytel | chão de folhas do bosque de folhosas |
| Sparse Grass (textura) | Amal Kumar | capim do campo aberto |
| Brick Wall 02 (textura) | Dimitrios Savva | prédios e casas de tijolo |
| Worn Plaster Wall (textura) | Dimitrios Savva | casas de reboco |
| Concrete Wall 004 (textura) | Dario Barresi, Charlotte Baglioni | prédios de concreto e lajes |
| Grey Roof 01 (textura) | Rob Tuytel | telhados das casas |
| Rusty Corrugated Iron (textura) | Charlotte Baglioni | telhados de zinco |
| Shrub 02 / Shrub 04 | Rico Cilliers | arbustos dos biomas de folhosas e campo |
| Weed Plant 02 | Rob Tuytel, Rico Cilliers | mato do campo e das vilas abandonadas |
| Street Lamp 01 | Josh Dean | postes de luz das cidades |
| Metal Trash Can | GurJas Studios | lixeiras nas ruas |
| Tree Small 02 (modelo, só como fonte) | Rico Cilliers | renderizado por `tools/bake_broadleaf_impostors.gd` no atlas `resources/textures/trees/broadleaf_cards.png` (árvore de folhas largas e a mesma seca); o modelo de 2 M polígonos fica em `assets/_source` |
| Quiver Tree 01 (modelo, só como fonte) | James Ray Cock, Dario Barresi, Rico Cilliers | árvore-aljava do bioma seco (no mesmo atlas) |

Baixados pela API oficial com `tools/download_polyhaven.py` (1k, glTF). Cada pasta tem `SOURCE.txt` com nome, autores, licença e link. Os modelos do mundo procedural são reduzidos (malha simplificada pelo próprio motor) por `tools/build_world_assets.gd`; os arquivos originais que só servem de fonte ficam fora do APK (`exclude_filter` em `export_presets.cfg`).

## Armas e veículos (OpenGameArt, CC0 1.0)

Licença conferida no campo "License(s)" da página de cada pacote.

| Recurso | Autor | Página | Uso |
|---|---|---|---|
| Survival Tools (picareta, versão "General", texturas PBR) | Gar5546x | https://opengameart.org/content/survival-tools | picareta (texturas reduzidas a 1K, AO/rugosidade/metal juntos numa textura ORM) |
| 3D Vehicles Pack (13 veículos de argila, sem UV) | mehrasaur (Inborn Ninja) | https://opengameart.org/content/3d-vehicles-pack | carcaças das estradas: levadas ao tamanho real, amassadas e pintadas/enferrujadas pelo shader `wreck.gdshader` (`tools/build_world_assets.gd`) |

## Autoria do projeto

| Recurso | Arquivo |
|---|---|
| Shaders do terreno (3 camadas PBR com mistura por altura) e das árvores (impostor com vento e translucidez) | `resources/materials/terrain.gdshader`, `tree_card.gdshader` |
| Céu encoberto, neblina, iluminação, terreno gerado, posicionamento da floresta e do posto | `tools/build_demo_map.gd` |
| Mundo procedural (relevo, cavernas, estradas e pintura das faixas, distribuição de floresta, carcaças, destroços e armas) e os shaders do terreno e das carcaças | `scripts/world/procedural/`, `resources/materials/world_terrain.gdshader`, `wreck.gdshader` |
| Pregos do taco (geometria), pintura do machado, empunhadura das armas | `tools/build_weapons.gd`, `scripts/weapons/` |
| Estalagmites, estalactites, blocos de minério, pedaços de pedra/carvão/ferro e toras (geometria procedural) e o shader de rocha com veios minerais | `tools/build_world_assets.gd`, `resources/materials/cave_rock.gdshader` |
| Ícones dos itens (desenhados a partir dos modelos 3D do próprio jogo) | `tools/build_items.gd`, `resources/icons/` |
| Roupas do personagem (geometria derivada da malha CC0) e ragdoll | `tools/build_survivor.gd` |
| Ícone `icon.svg`, shader `dev_grid`, cenário de calibração | raiz, `resources/materials/`, `tools/build_test_gym.gd` |

## Removidos

| Recurso | Motivo |
|---|---|
| Corpo, roupas e cabeça Quaternius (Universal Base Characters e Modular Character Outfits – Fantasy, CC0) | substituídos pelo personagem enviado pelo dono do projeto (etapa 6) |
| Gravel Floor (Poly Haven, CC0) | não era usado no mapa |
| Roupas geradas a partir da malha do corpo (etapa 4) e os tecidos Denim Fabric, Cotton Jersey, Brown Leather e Fabric Leather 02 (Poly Haven, CC0) | substituídas pela roupa modelada do pacote de roupas (etapa 5): as cascas geradas deixavam o relevo dos músculos e dos dedos dos pés aparecer e tinham barras serrilhadas |
| Corpo "Superhero" do Universal Base Characters (exceto cabeça) | proporções de super-herói; trocado pelo esqueleto "Regular" do pacote de roupas (etapa 5) |
| Braços em primeira pessoa procedurais (19 ossos) | substituídos pelo corpo humano completo (o mesmo nas duas câmeras) |
| Forest Ambience (TinyWorlds) e Ambient Bird Sounds (isaiah658), OpenGameArt, CC0 | etapa 7: o ambiente passou a ser só o vento, com intensidade variável |
| HDRI "Misty Pines" (Poly Haven, CC0) | o céu mostrava troncos pintados "pendurados" acima das árvores reais; trocado por céu procedural (mais leve no Android) |

## Avaliados e rejeitados

| Recurso | Motivo |
|---|---|
| Mixamo (Adobe) | Os termos permitem usar em jogos, mas proíbem redistribuir os arquivos brutos; num repositório público, versioná-los seria redistribuição. |
| Universal Base Characters — corpo-base "Regular" | Só na versão paga (Source) do pacote; a versão gratuita (CC0) tem apenas as proporções "Superhero". O esqueleto e a pele "Regular" vêm do pacote de roupas gratuito, que os inclui. |
| Modular Character Outfits – Fantasy: Ranger completo (capuz, ombreira, braçadeiras) | estética de fantasia |
| "Footsteps (leather, cloth, armor)", OpenGameArt (HaelDB) | OGA-BY 3.0 (exige atribuição); havia alternativas CC0 |
| "12 wet towel hitting/falling/punching floor sounds", OpenGameArt (qubodup) | a página diz CC0, mas o arquivo do pacote declara MIT/zlib/BSD (exige manter o aviso); trocado por um pacote CC0 sem ambiguidade |
| Pacotes de áudio no site kenney.nl | o site bloqueia download automatizado; os mesmos sons CC0 foram obtidos pela página oficial do Kenney no OpenGameArt |
| Animação Idle_Shield (UAL2) como guarda | postura de escudo, com um braço cruzado no peito; a guarda usa o quadro final de Melee_Hook_Rec (punhos diante do rosto) |
| Quaternius Universal Animation Library "Pro" (strafe, giro no lugar, paradas) | paga; giro no lugar, parada e inclinação foram feitos com a física sobre as capturas gratuitas (ver docs/ETAPA_05_JOGABILIDADE.md) |
| "fps arms (rigged only)", OpenGameArt (autor: para), CC0 | só rig, sem animações. |
| "LowPoly Animated Sword (W/12 Animations)", OpenGameArt (autor: zisongbr), CC0 | animações de espada só em `.blend`; as armas usam os golpes de espada da UAL2 (Sword_Regular_A/B) e a postura Sword_Idle da UAL1. |
| TreeChopping (UAL2) como golpe de combate do machado | é um laço de cortar lenha; na etapa 8 passou a ser usado só para cortar árvores, um ciclo por golpe, com o impacto marcado à mão (0,2 s) |
| Dark Rock (Poly Haven, CC0) | escura demais para as paredes das cavernas (média 33/255): a rocha ficava preta mesmo sob a lanterna |
| Pacote "wood crack hit destruction" (Independent.nu) | sem arquivo de licença no pacote baixado; os sons de madeira vêm do pacote CC0 do rubberduck, já verificado |
| Low World first-person arms (itch.io) | não é CC0 e estava indisponível. |

## Como adicionar um asset

1. Baixar da fonte original e conferir a licença na página e nos arquivos do pacote.
2. Colocar em `assets/<categoria>/<nome>/` junto com o arquivo de licença original (ou `SOURCE.txt`).
3. Registrar aqui: nome, autor, link, licença, uso.
4. Se a licença exigir atribuição, incluir também na tela de créditos do jogo.
