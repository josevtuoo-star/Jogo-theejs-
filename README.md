# Sobrevivência — v0.04

Jogo de sobrevivência no estilo DayZ / The Walking Dead, feito no **Godot 4** para
**Android** (funciona também no PC). Agora num **pedaço real do sertão da Paraíba**: Faisqueiro,
na PB-394 (o ponto -6,93394, -38,45759), com relevo, estradas, açudes e casas nos lugares reais.

## Como abrir

1. Instale o **Godot Engine 4** (4.3 ou mais novo; no 4.4+ a física usa a **Jolt**) — no
   Android pela Play Store, ou no PC.
2. No Godot: **Importar** → escolha o `project.godot` (ou o `.zip` do projeto) → **Importar e editar**.
3. Na primeira vez ele importa modelos, texturas e sons (pode levar um minuto).
4. Aperte **▶ (Executar projeto)**.

## Controles

| Ação | Celular | PC | Controle |
| --- | --- | --- | --- |
| Andar / correr | analógico no lado esquerdo; dedo além do anel externo = correr | WASD + Shift | analógico esquerdo |
| Olhar | arraste no lado direito da tela | mouse (clique prende, Esc solta) | analógico direito |
| Pular / nadar mais rápido | **PULAR** | Espaço | A |
| Agachar / rolar / mergulhar | **AGACHAR** (correndo vira **ROLAR**) | C ou Ctrl | B |
| Usar | **USAR** — mostra a ação: **PEGAR (item e peso)**, **SENTAR**... | E | Y |
| Sacar / guardar a arma | **ARMA** | Q | RB |
| Equipamento (mochila) — largar, empunhar, **comer/beber** | **MOCHILA** | Tab ou I | Start |
| Configurações | **⚙** | O ou F10 | — |
| Soco (combo) | **SOCO** | clique esquerdo ou F | X |
| 1ª / 3ª pessoa | **1ª/3ª** | V | analógico direito (apertar) |
| Recomeçar | **↺** (ou no painel ⚙) | R | Select |

## Novidades da v0.04

### O mapa real: Faisqueiro e a PB-394 (2,6 km × 4,6 km)
- **Relevo real** (Copernicus GLO-30): os morros e baixadas de verdade (de -18 m a +115 m em
  relação à vila).
- **Chão pintado pela imagem de satélite** (Sentinel-2, outubro de 2025, estação seca): caatinga
  escura, roçados claros, verde perto da água; de perto, barro rachado, pedrinhas e capim.
- **Estradas reais**: a **PB-394 (Rodovia Chico Aristides)** asfaltada e 50+ estradas de terra
  (incluindo o Acesso a Gravatá), com o terreno aplainado embaixo.
- **238 casas nos lugares das construções reais** (do mapeamento por satélite): casas de
  reboco pintado e desbotado, barrado escuro, descascando, telha colonial ou zinco, porta e
  janelas abertas (dá para entrar), algumas sem telhado; móveis e **coisas para achar dentro**
  (comida, água, ferramentas, panelas e, às vezes, uma arma).
- **10 açudes** cavados onde o satélite mostra água (dá para nadar) e o **leito seco do
  Rio Piranhas**.
- **Caatinga gerada pelo satélite**: muita moita seca, arvoretas tortas sem folha, cactos e
  pés de pau com folha perto da água.
- **Capela "Espaço São José"** (branca, com cruz) e a **torre de vigia** no morro mais alto perto
  da vila; **carros abandonados** na rodovia; placa "FAISQUEIRO / PB-394".
- O mundo é montado em **blocos de 160 m em volta de você** (terreno com menos detalhe longe,
  colisão só perto, árvores de longe como "impostores" — fotos 3D em cartões). Por isso o mapa
  grande roda no celular.

### Personagem novo
- Corpo humano com **rosto, barba e cabelo raspado**, roupa de **camponês** (camisa, calça,
  botas) — peças CC0 da Quaternius feitas para o mesmo esqueleto das animações.
- Animação nova de **comer e beber** (Universal Animation Library 2): no painel MOCHILA, toque
  **COMER**/**BEBER** — a mão busca o item na mochila/cinto e leva à boca (tira cansaço).

### Configurações gráficas (botão ⚙)
- **Qualidade pronta**: Baixa, Média, Alta, Ultra (o celular começa em Média).
- Ajuste separado: **sombras** (desligadas/baixa/média/alta) e **distância das sombras**,
  **resolução 3D** (50–100%), **antisserrilhado** (2x/4x), **distância de visão** (250–1500 m),
  **densidade da caatinga**, **grama perto**, **neblina**, **cor final**, **limite de FPS**
  (30/60/90/120/sem), **brilho**, **campo de visão**, **sensibilidade** e **mostrar FPS**.
- Tudo salvo no aparelho. Dica: se o FPS cair, baixe Resolução 3D, Sombras e Vegetação.

### Física e correções
- Física **Jolt** no Godot 4.4+ (mais estável com muitos objetos; no 4.3 continua a padrão).
- **"Pose T" no ar** corrigida: a pose de pulo só entra em quedas de verdade, misturada pela
  metade (antes abria os braços num degrau ou preso numa quina).
- **Preso em móvel/quina** ("No ar" parado): o personagem agora escorrega para fora.
- **Galão** vai amarrado na lateral da mochila (não fica mais pendurado batendo nas coisas).
- Volume da água dos açudes mais alto (nadar não "liga e desliga").

## Da v0.03 (continua valendo)

### Itens com peso, roupa e mochila — nada some
- O personagem usa **roupa** (jaqueta de lona, camisa xadrez, calça jeans, cinto, botas,
  luvas sem dedos, gorro), com trama do tecido, desgaste e barro, e uma **mochila** nas costas.
- **Tudo que ele pega tem peso e vai para um lugar do corpo, à vista**:
  - armas longas penduradas **nas costas** (até duas, em X, por cima da mochila);
  - machado, pá, frigideira e kit médico **amarrados nas laterais** da mochila;
  - panela, chaleira e galão **pendurados embaixo**; caneca **em cima**;
  - lanterna e garrafa **no cinto**;
  - comida, munição e fósforos **dentro da mochila** (32 litros; ela **estufa** conforme enche).
- **Pegar** é um movimento completo com IK nos braços: vira para o item, dá um passo, **agacha**
  e inclina o tronco (itens no chão) ou só estende o braço (mesa), a mão chega por cima e
  fecha no item, levanta, olha o item na frente do peito e leva até o lugar dele (por cima do
  ombro para as costas/mochila, para o quadril no cinto). Cada lugar tem seu som (couro, cinto,
  metal, zíper/pano).
- **Largar** (painel MOCHILA → LARGAR): a mão vai até o lugar do item, tira, traz para frente e
  solta — o item cai com física de verdade (peso, quique, barulho conforme o material).
- **Peso**: o total aparece no HUD e no painel. Acima de ~6 kg o personagem fica mais lento
  (até 38% mais lento), cansa mais rápido correndo, pula menos, inclina o corpo para frente e
  o equipamento chacoalha nos passos. Limite de 40 kg.
- **Física secundária**: a mochila balança com molas ao andar, parar e virar; panela e itens do
  cinto são pêndulos (ficam sempre pendurados para baixo e balançam com o corpo).

### Armas: sacar, segurar e guardar
- **ARMA** (Q): a mão direita sobe por cima do ombro, pega a arma das costas e traz para a
  frente; a mão esquerda encontra o guarda-mão. Segura com **as duas mãos (IK)**, coronha no
  ombro, apontando para onde a câmera olha, com atraso de mola (a arma tem peso). O corpo fica
  de lado (ombro esquerdo à frente) como quem segura um rifle; correndo, a arma desce e vai
  para o lado. Em 1ª pessoa a arma aparece embaixo, à direita.
- Guardar faz o caminho inverso. Ao nadar ou sentar a arma vai para as costas sozinha.
- Armas: **AK-47**, **M4A1**, **escopeta** e **rifle de caça** espalhadas pelo mapa (o rifle no
  acampamento, a escopeta perto da viatura, a AK no alto da torre, a M4 numa cabana a oeste).
- Ainda **não atira** (próxima etapa).

### Animações com um "extra" em cada uma
- **Parado**: respiração (peito e ombros sobem; mais rápida e funda depois de correr) e, depois
  de alguns segundos, o personagem **olha em volta**; agachado ele vigia mais rápido.
- **Andar/correr**: inclina para frente com carga pesada; a mochila e os itens pendurados
  balançam; o equipamento chacoalha a cada passo.
- **No ar**: os braços abrem para equilibrar.
- **Nadando**: cabeça levantada para fora d'água (abaixa ao mergulhar).
- **Empurrando**: cabeça baixa e tronco à frente fazendo força.
- **Soco**: o tronco gira junto com o golpe (jab para um lado, direto para o outro) e a cabeça
  segura o olhar no alvo.
- **Pegar / largar / sacar / guardar / abrir porta**: mãos guiadas por IK até o objeto real.

### Sons gravados (no lugar dos sintetizados)
- Passos em **grama, terra, asfalto e madeira** (piso das cabanas e da torre), queda, roupa,
  couro, cinto, manuseio de arma e trava, socos, batidas de **madeira, metal, lata e vidro**,
  portas abrindo e fechando, **pássaros e insetos** (ambiente vindo das árvores mais próximas).
- Continuam gerados por código só o vento (com rajadas), a água do lago, espirros, braçadas e
  bolhas. A respiração sintetizada (que soava mal) foi retirada.

## Arquivos

```
project.godot                 configuração (Compatibility, ideal para Android; Jolt no 4.4+)
scenes/main.scn               cena principal (céu, sol, jogador, mundo, HUD)
scenes/player.tscn            personagem (colisão, modelo, câmera)
assets/mapa_real/             dados do lugar real: altura.res (relevo), satelite.png, mascara.png
                              (asfalto/terra/água), vegetacao.png (caatinga/verde/roçado), dados.json
                              (estradas, 238 casas, açudes, rio, lugares)
assets/personagem/            corpo, roupa, cabelo/barba e animações extras (Quaternius, CC0)
assets/natureza/              cactos (Quaternius, CC0) e fotos das árvores para os impostores
assets/texturas/              detalhe do solo e reboco (geradas para o projeto)
assets/ual/, modelos/, cenario/, armas/, sfx/   como na v0.03
scripts/mundo_real.gd         mundo em blocos: terreno, colisão, caatinga, casas, estradas, açudes
scripts/config.gd, settings_ui.gd   configurações gráficas e o painel ⚙
scripts/player.gd, procedural_body.gd, equipamento.gd, itens.gd, item.gd, inventory_ui.gd
scripts/sfx.gd, audio.gd, ambience.gd, touch_controls.gd, inputs.gd, water.gd, seat.gd...
shaders/terreno_real.gdshader, parede.gdshader, water.gdshader, post.gdshader
ferramentas/                  gerar_mapa_real.gd (cena + impostores), testes.gd (31 testes),
                              extrair_modelos.gd e dados_reais/ (scripts Python que baixam e
                              processam relevo, satélite, estradas e casas)
```

## Créditos

- Personagem, roupas, cabelo e animações: **Quaternius** — Universal Animation Library 1 e 2,
  Universal Base Characters, Modular Character Outfits; cactos do Ultimate Nature Pack —
  **CC0** (https://quaternius.com; obtidos dos espelhos CC0 `Dallolz/moorfall-assets` e
  `trebeljahr/quaternius-showcase` no GitHub).
- Cenário, veículos, móveis, ferramentas, mochilas, texturas e armas: pacotes **Models /
  Textures1 / Textures2 / GunsExplosives** enviados para o projeto.
- Relevo: **Copernicus DEM GLO-30** — © DLR e.V. 2010-2014 e © Airbus Defence and Space GmbH
  2014-2018, fornecido pelo programa COPERNICUS da União Europeia e ESA.
- Imagem de satélite: contém dados modificados do **Copernicus Sentinel-2** (2025), ESA.
- Estradas, rio e construções: **Overture Maps Foundation** (dados do **© OpenStreetMap**
  contributors, ODbL; construções de Google Open Buildings / Microsoft, CC BY 4.0 / ODbL).
- Sons: Kenney (CC0), The Free Firearm Sound Library e Gun reload sounds (CC0), demo Truck
  Town do godot-demo-projects (MIT).
- Código, processamento dos dados, materiais e sons sintetizados: feitos para este projeto.
