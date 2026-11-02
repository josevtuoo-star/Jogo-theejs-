# Procedência e licenças dos assets

Regra do projeto: cada recurso tem a licença verificada **por arquivo** na fonte original antes de entrar no repositório. Recursos sem licença identificável, extraídos de jogos comerciais ou com restrição incompatível com o uso pretendido não são aceitos. Como este repositório é **público**, recursos cuja licença proíbe redistribuir os arquivos brutos também ficam de fora.

Todos os assets de terceiros em uso são **CC0 1.0** (domínio público): uso comercial permitido, sem atribuição obrigatória. O personagem jogável é do dono do projeto. Mesmo assim, os autores estão creditados abaixo e em `SOURCE.txt` / `LICENSE_*.txt` dentro de cada pasta.

## Personagem e animações

| Recurso | Autor | Origem | Licença verificada | Uso no jogo |
|---|---|---|---|---|
| Sobrevivente (`assets/characters/survivor/Sobrevivente.fbx`): malha com gorro, jaqueta, calça cargo, botas e luvas, esqueleto de 65 ossos (convenção Mixamo) | Dono do projeto | enviado pelo dono do projeto em 02/11/2026 para substituir o personagem | uso autorizado pelo dono do projeto | personagem jogável; ossos renomeados para os nomes do jogo e animações retargetadas por `tools/retarget_animations.gd` e `tools/build_survivor.gd` |
| Universal Animation Library (Standard, FBX Unreal) | Quaternius | https://opengameart.org/content/universal-animation-library (também em quaternius.itch.io) | CC0 1.0 (página do OpenGameArt e `License.txt` no pacote) | 17 animações retargetadas: parado, andar, trotar, correr, agachado, salto, queda, aterrissagem, socos, ferimentos, interagir, pegar, empurrar, morte |
| Universal Animation Library 2 (Standard, GLB) | Quaternius | https://opengameart.org/content/universal-animation-library-2 | CC0 1.0 (página do OpenGameArt) | 8 animações: gancho e sua recuperação (o quadro final é a guarda de defesa), impacto na guarda (Sword_Block), recuo, levantar, consumir, abrir baú, andar carregando |

Os pacotes de animação originais ficam em `assets/_source/` (fora do Git e do APK). `tools/retarget_animations.gd` gera `resources/animations/survivor_body.res` (retarget por delta no espaço do mundo com alinhamento de poses, pois o personagem está em T, + medição de passada e quadros de contato). `tools/build_survivor.gd` monta o personagem (materiais PBR por superfície, cabeça separada para a primeira pessoa) e o ragdoll.

## Sons (OpenGameArt, todos CC0 1.0)

Licença conferida no campo "License(s)" da página de cada pacote e nos arquivos de licença dentro dos pacotes (Kenney: `license.txt`; Corsica_S: `readme.txt`). Convertidos para OGG mono com volume normalizado por `tools/prepare_audio.py`; origem de cada arquivo em `assets/audio/SOURCES.md`.

| Pacote | Autor | Página | Uso |
|---|---|---|---|
| Fantozzi's Footsteps (Grass/Sand & Stone) | Fantozzi | https://opengameart.org/content/fantozzis-footsteps-grasssand-stone | passos na terra e na pedra |
| 50 RPG sound effects | Kenney | https://opengameart.org/content/50-rpg-sound-effects | passos na grama, roupa, interruptor, couro |
| 42 Snow and Gravel Footsteps | Corsica_S (extração: qubodup) | https://opengameart.org/content/42-snow-and-gravel-footsteps | passos no gelo |
| 37 hits/punches | Independent.nu | https://opengameart.org/content/37-hitspunches | soco acertando o corpo |
| 75 CC0 breaking/falling/hit sfx | rubberduck | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | impactos em madeira, metal e genéricos, objetos caindo, corpo caindo, defesa |
| Metal Impact Sounds | BMacZero | https://opengameart.org/content/metal-impact-sounds | metal tilintando, golpe na parede |
| Swishes Sound Pack | artisticdude | https://opengameart.org/content/swishes-sound-pack | braço cortando o ar |
| 15 vocal male strain/hurt/pain/jump sounds | qubodup | https://opengameart.org/content/15-vocal-male-strainhurtpainjump-sounds | esforço, dor, morte |
| Jump Landing | Macro | https://opengameart.org/content/jump-landing | aterrissagem |
| Fire Crackling | AntumDeluge | https://opengameart.org/content/fire-crackling | fogueira |
| Forest Ambience | TinyWorlds | https://opengameart.org/content/forest-ambience | ambiente da floresta |
| Ambient Bird Sounds | isaiah658 | https://opengameart.org/content/ambient-bird-sounds | passarinhos |

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

Baixados pela API oficial com `tools/download_polyhaven.py` (1k, glTF). Cada pasta tem `SOURCE.txt` com nome, autores, licença e link.

## Autoria do projeto

| Recurso | Arquivo |
|---|---|
| Shaders do terreno (3 camadas PBR com mistura por altura) e das árvores (impostor com vento e translucidez) | `resources/materials/terrain.gdshader`, `tree_card.gdshader` |
| Céu encoberto, neblina, iluminação, terreno gerado, posicionamento da floresta e do posto | `tools/build_demo_map.gd` |
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
| "LowPoly Animated Sword (W/12 Animations)", OpenGameArt (autor: zisongbr), CC0 | animações de espada só em `.blend`; reavaliar na etapa de armas brancas. |
| Low World first-person arms (itch.io) | não é CC0 e estava indisponível. |

## Como adicionar um asset

1. Baixar da fonte original e conferir a licença na página e nos arquivos do pacote.
2. Colocar em `assets/<categoria>/<nome>/` junto com o arquivo de licença original (ou `SOURCE.txt`).
3. Registrar aqui: nome, autor, link, licença, uso.
4. Se a licença exigir atribuição, incluir também na tela de créditos do jogo.
