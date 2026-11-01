# Sobrevivência — v0.03

Jogo de sobrevivência no estilo DayZ / The Walking Dead, feito no **Godot 4** para
**Android** (funciona também no PC). Personagem e animações da **Universal Animation Library**
(Quaternius, CC0); cenário, carros, móveis, ferramentas e armas do pacote de modelos enviado
(Models / Textures / GunsExplosives); sons gravados CC0.

## Como abrir

1. Instale o **Godot Engine 4** (4.3 ou mais novo) — no Android pela Play Store, ou no PC.
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
| Usar | **USAR** — mostra a ação: **PEGAR (item e peso)**, **ABRIR/FECHAR PORTA**, **SENTAR** | E | Y |
| Sacar / guardar a arma | **ARMA** | Q | RB |
| Equipamento (mochila) | **MOCHILA** | Tab ou I | Start |
| Soco (combo) | **SOCO** | clique esquerdo ou F | X |
| 1ª / 3ª pessoa | **1ª/3ª** | V | analógico direito (apertar) |
| Recomeçar | **↺** | R | Select |

## Novidades da v0.03

### Mapa de 1 km × 1 km, pós-apocalíptico
- Terreno com morros, estrada asfaltada atravessando o mapa, estradas de terra, céu fechado,
  neblina e cores lavadas (sem vida, como em The Walking Dead).
- **Acampamento** no centro (onde o jogo começa): cabana, picape, viatura do xerife, fogueira
  apagada com pedras e troncos.
- **Seis cabanas** com móveis (cama, mesa, fogão, estante, armário) e **porta que abre e fecha**
  (o personagem leva a mão até a maçaneta); cadeiras para **sentar**; som com eco lá dentro.
- **Torre de vigia** num morro, **lago**, **carros abandonados** pela estrada e no mato.
- Floresta de árvores secas e pinheiros mortos, troncos caídos, tocos, pedras, rochedos,
  arbustos, samambaias e grama alta (desenhados em lotes e somem de longe — leve no celular).

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
project.godot                 configuração (renderizador Compatibility, ideal para Android)
scenes/main.scn               mapa de 1 km (gerado), céu, luz, HUD
scenes/player.tscn            personagem (colisão, modelo, câmera)
assets/ual/                   Universal Animation Library (personagem + animações) e licença
assets/modelos/               objetos do pacote prontos para usar (com colisão) e armas
assets/cenario/, assets/armas/ texturas do pacote (reduzidas para o celular)
assets/mapa/                  blocos do terreno e máscara das estradas
assets/sfx/                   sons gravados
scripts/player.gd             movimento, física, ações, nado, socos, câmeras e animações
scripts/procedural_body.gd    IK de pés e braços, inclinação, olhar, respiração e extras
scripts/equipamento.gd        roupa, mochila, lugares no corpo, pegar/guardar/largar, armas
scripts/itens.gd              tabela de itens (peso, volume, onde vão no corpo)
scripts/item.gd               item no mundo (física, som, PEGAR)
scripts/inventory_ui.gd       painel do equipamento (MOCHILA)
scripts/door.gd, seat.gd      porta com dobradiça, assento
scripts/terreno.gd            colisão de cada bloco do terreno
scripts/sfx.gd, audio.gd, ambience.gd   sons, eco/abafado, ambiente
scripts/touch_controls.gd, inputs.gd    controles de toque, teclado e controle
shaders/                      terreno, roupa, água e cor final
fontes/                       arquivos originais do pacote (ignorados pelo Godot)
```

## Créditos

- Personagem e animações: **Universal Animation Library (Standard)** —
  [Quaternius](https://quaternius.com), **CC0** (`assets/ual/License.txt`).
- Cenário, veículos, móveis, ferramentas, mochilas e texturas: pacote **Models / Textures1 /
  Textures2** enviado para o projeto. Armas (AK-47, M4A1, escopeta): pacote **GunsExplosives**
  enviado para o projeto.
- Sons: [Kenney — Impact Sounds](https://kenney.nl/assets/impact-sounds) e
  [Kenney — RPG Audio](https://kenney.nl/assets/rpg-audio) (CC0);
  [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) e
  [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) (CC0);
  pássaros/insetos do demo Truck Town de
  [godot-demo-projects](https://github.com/godotengine/godot-demo-projects) (MIT, © Godot Engine contributors).
- Código, mapa, materiais procedurais e sons sintetizados: feitos para este projeto.

## Ferramentas

- `ferramentas/gerar_mapa.gd` — gera `scenes/main.scn` e `assets/mapa/` (rode com
  `godot --rendering-driver opengl3 -s res://ferramentas/gerar_mapa.gd`; precisa de janela).
- `ferramentas/extrair_modelos.gd` — transforma os FBX do pacote em `assets/modelos/` (copie
  `fontes/Vegetation.fbx` para `assets/cenario/` e os das armas para `assets/armas/` antes).
- `ferramentas/testes.gd` — 23 testes automáticos (andar, pegar, guardar, sacar e guardar a
  arma, largar, peso, porta, nadar): `godot --headless -s res://ferramentas/testes.gd`.
