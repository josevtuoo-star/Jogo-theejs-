# Procedência e licenças dos assets

Regra do projeto: cada recurso tem a licença verificada **por arquivo** na fonte original antes de entrar no repositório. Recursos sem licença identificável, extraídos de jogos comerciais ou com restrição incompatível com o uso pretendido não são aceitos. Como este repositório é **público**, recursos cuja licença proíbe redistribuir os arquivos brutos também ficam de fora.

Todos os assets de terceiros em uso são **CC0 1.0** (domínio público): uso comercial permitido, sem atribuição obrigatória. Mesmo assim, os autores estão creditados abaixo e em `SOURCE.txt` / `LICENSE_*.txt` dentro de cada pasta.

## Personagem e animações

| Recurso | Autor | Origem | Licença verificada | Uso no jogo |
|---|---|---|---|---|
| Universal Base Characters — Superhero Male (malha, esqueleto de 65 ossos, texturas PBR, olhos, cabelo raspado, barba, sobrancelhas) | Quaternius | https://quaternius.itch.io/universal-base-characters | CC0 1.0 (página: "Asset license: Creative Commons Zero v1.0 Universal"; `License_Standard.txt` no pacote, copiado em `assets/characters/survivor/LICENSE_Quaternius_UBC.txt`) | corpo do sobrevivente; os arquivos glTF tiveram só os nomes das texturas corrigidos (o pacote referencia `*_png.png` inexistentes) |
| Universal Animation Library (Standard, FBX Unreal) | Quaternius | https://opengameart.org/content/universal-animation-library (também em quaternius.itch.io) | CC0 1.0 (página do OpenGameArt e `License.txt` no pacote) | 17 animações retargetadas: parado, andar, trotar, correr, agachado, salto, queda, aterrissagem, socos, ferimentos, interagir, pegar, empurrar, morte |
| Universal Animation Library 2 (Standard, GLB) | Quaternius | https://opengameart.org/content/universal-animation-library-2 | CC0 1.0 (página do OpenGameArt) | 6 animações: gancho, recuo, levantar, consumir, abrir baú, andar carregando |

Os pacotes originais ficam em `assets/_source/` (fora do Git e do APK). `tools/retarget_animations.gd` gera `resources/animations/survivor_body.res` (retarget por delta no espaço do mundo + medição de passada e quadros de contato). `tools/build_survivor.gd` gera as roupas (jaqueta, calça e botas modeladas a partir da malha do corpo, com tecidos da Poly Haven) e o ragdoll.

## Cenário (Poly Haven, CC0 1.0 — https://polyhaven.com/license)

| Recurso | Autores | Uso |
|---|---|---|
| Forest Floor (textura) | eye-candy.xyz | chão de floresta (terreno) |
| Leafy Grass (textura) | Charlotte Baglioni | grama da clareira |
| Brown Mud Leaves 01 (textura) | Rob Tuytel | estrada de terra e acampamento |
| Gravel Floor (textura) | Jenelle van Heerden, Matterfield | reserva para estradas de cascalho |
| Pine Sapling Small (texturas da casca) | Rob Tuytel, Rico Cilliers | troncos das árvores |
| Fir Sapling Medium (modelo, só como fonte) | Rob Tuytel, Rico Cilliers | renderizado por `tools/bake_tree_impostors.gd` no atlas `resources/textures/trees/fir_cards.png` (impostores das árvores); o modelo de 2,3 M polígonos não vai para o jogo |
| Denim Fabric / Cotton Jersey / Brown Leather / Fabric Leather 02 (texturas) | Rob Tuytel; colormass, Rico Cilliers; Rob Tuytel; Rob Tuytel | calça, jaqueta, botas |
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

## Removidos nesta etapa

| Recurso | Motivo |
|---|---|
| Braços em primeira pessoa procedurais (19 ossos) | substituídos pelo corpo humano completo (o mesmo nas duas câmeras) |
| HDRI "Misty Pines" (Poly Haven, CC0) | o céu mostrava troncos pintados "pendurados" acima das árvores reais; trocado por céu procedural (mais leve no Android) |

## Avaliados e rejeitados

| Recurso | Motivo |
|---|---|
| Mixamo (Adobe) | Os termos permitem usar em jogos, mas proíbem redistribuir os arquivos brutos; num repositório público, versioná-los seria redistribuição. |
| Universal Base Characters — proporções "Regular" | Só na versão paga do pacote; a versão gratuita (CC0) tem apenas as proporções "Superhero". |
| "fps arms (rigged only)", OpenGameArt (autor: para), CC0 | só rig, sem animações. |
| "LowPoly Animated Sword (W/12 Animations)", OpenGameArt (autor: zisongbr), CC0 | animações de espada só em `.blend`; reavaliar na etapa de armas brancas. |
| Low World first-person arms (itch.io) | não é CC0 e estava indisponível. |

## Como adicionar um asset

1. Baixar da fonte original e conferir a licença na página e nos arquivos do pacote.
2. Colocar em `assets/<categoria>/<nome>/` junto com o arquivo de licença original (ou `SOURCE.txt`).
3. Registrar aqui: nome, autor, link, licença, uso.
4. Se a licença exigir atribuição, incluir também na tela de créditos do jogo.
