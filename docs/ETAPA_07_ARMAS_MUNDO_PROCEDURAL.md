# Etapa 7 — Armas brancas, mundo procedural com cavernas e som só do vento

Pedidos do dono do projeto (02/11/2026), com cinco imagens de referência (picareta, machado de bombeiro vermelho, taco com pregos, carro enferrujado na mata com samambaias, rodovia na floresta tomada por carros, caminhões e uma van abandonados, com malas, sacos e latas):
- deixar personagem e animações como estão;
- tirar a trilha sonora e os pássaros; deixar só o vento, conforme a intensidade do vento;
- o fôlego do personagem estava rápido demais;
- adicionar picareta, machado e taco com pregos, como nas imagens;
- mapa procedural como o do Minecraft, carregado por pedaços (chunks), com cavernas, no estilo pós-apocalipse zumbi e com a ambientação das fotos.

O personagem e as animações existentes não mudaram. As armas trouxeram três animações novas (abaixo), sem alterar as antigas.

## 1. Som: só o vento, e fôlego natural

- **Trilha e pássaros removidos.** Os arquivos `ambience/floresta.ogg` e `ambience/passaros.ogg` e o nó de ambiente saíram do jogo.
- **Vento com intensidade.** O novo singleton `Wind` (`scripts/world/wind.gd`) calcula uma intensidade (0–1) por dois ruídos: um lento (o tempo muda) e um de rajadas. A mesma intensidade controla:
  - o volume do som de vento (de −34 a −6 dB);
  - o tom (0,85 a 1,15);
  - o filtro passa-baixa do barramento "Vento": vento fraco é um sopro abafado, forte é chiado aberto;
  - o balanço das árvores (parâmetro global `wind_intensity` no shader dos impostores). A copa balança mais e mais rápido quando o vento sopra.
- **O arquivo de vento** agora é um ruído largo e constante. Rajadas e variação vêm do jogo, não do arquivo, então não há laço perceptível.
- **Fôlego.** O arquivo original tinha três respirações em 3,2 s. Tocado em laço, dava cerca de 57 por minuto, ofegante demais. Agora:
  - ele foi separado em três respirações avulsas;
  - o jogo toca uma de cada vez, com intervalo pelo esforço: 3,2 s depois de um trote, 1,6 s depois de correr muito, com variação;
  - o fôlego só aparece depois de correr de verdade e se acalma em cerca de 25 s;
  - o teste mede de 12 a 42 respirações por minuto.

## 2. Armas: picareta, machado de bombeiro, taco com pregos

`tools/build_weapons.gd` monta as três malhas e os dados (`resources/weapons/*.tres`, classe `WeaponData`):

| Arma | Origem | Montagem | Rápido | Carregado | Alcance além do punho |
|---|---|---|---|---|---|
| Picareta | "Survival Tools", Gar5546x (CC0) | texturas PBR reduzidas a 1K; AO, rugosidade e metal numa textura ORM | 26 | 38–66 | 0,66 m |
| Machado de bombeiro | Wooden Axe 02, Poly Haven (CC0) | aumentado para 88 cm; a cabeça é pintada de vermelho gasto e o fio da lâmina fica no aço | 30 | 44–75 | 0,68 m |
| Taco com pregos | Baseball Bat, Poly Haven (CC0) | 16 pregos enferrujados cravados 3 cm no barril, tortos, saindo 7–9 cm | 22 | 32–54 | 0,72 m |

- **Na mão.** A arma presa ao osso da mão direita. A pegada é calculada da anatomia da própria mão:
  - direção dos dedos;
  - eixo do mínimo ao indicador;
  - palma.

  Então o cabo fica no punho fechado, a cabeça sai do lado do polegar e o lado que golpeia fica para fora. Conferido em renderizações de 1ª e 3ª pessoa.
- **Animações novas, retargetadas para o seu personagem como as outras.**
  - `weapon_idle`: postura com a arma.
  - `weapon_swing_a`: golpe rápido, um corte diagonal.
  - `weapon_swing_b`: golpe amplo e carregado, que segura a preparação enquanto o botão está apertado.

  Os golpes de espada originais terminam erguendo a arma de novo. A pose é congelada no fim do golpe e a transição volta à postura. O quadro de impacto é aquele em que a mão está mais à frente do peito (com arma o braço também se estica na preparação, atrás do corpo).
- **Combate.** O mesmo sistema de impacto pelo braço real, agora com o comprimento da arma somado ao alcance:
  - dano, impulso, velocidade e recuperação vêm de cada arma, e as pesadas são mais lentas;
  - o machado acerta a 0,45 m além de onde o soco já não chega;
  - o som do golpe fica mais grave e mais forte quanto mais pesada a arma;
  - no acerto soa também o material da arma: madeira do taco, aço do machado e da picareta.
- **Pegar, trocar e soltar.**
  - As armas são corpos físicos de verdade: caem, rolam e soam ao bater.
  - **USAR** pega a arma; se já havia outra na mão, ela cai no lugar da nova.
  - **G** (teclado), **direcional para baixo** (controle) ou o botão **SOLTAR** solta a arma. O botão SOLTAR aparece na tela de toque só com arma na mão.
- **Correção na interação.** Durante o gesto de pegar, a cabeça se move e o raio da câmera podia escapar de um objeto fino, como um cabo no chão, cancelando a ação. Agora basta o objeto continuar ao alcance do braço no quadro de contato da mão.

## 3. Mundo procedural infinito, por pedaços, com cavernas

A cena principal agora é `scenes/world/mundo.tscn`. O mapa de demonstração (`scenes/demo/demo_forest.tscn`) continua no projeto, com as três armas no posto militar.

### 3.1 Como o mundo é gerado (`scripts/world/procedural/world_generator.gd`)

Como no Minecraft, tudo sai de uma semente. O mesmo pedaço é sempre igual, em qualquer ordem, e pode ser gerado em segundo plano. A diferença é que o terreno é liso, sem blocos, no estilo realista do jogo.

O terreno é um **campo de densidade 3D** (rocha/terra positiva, ar negativa), feito de quatro partes:
- **Relevo.** Planícies onduladas, morros e serras, com cristas onde o ruído de montanha é alto. A altura vai de −4 a 45 m.
- **Estradas.**
  - Rodovias norte-sul a cada 640 m e estradas vicinais leste-oeste entre elas, serpenteando.
  - O leito da estrada ignora as serras, então a estrada corta os morros. O corte e o aterro têm talude: a rampa alarga com o desnível, sem paredes a prumo.
  - O asfalto é velho, com faixa amarela tracejada no meio e brancas nas bordas, apagadas pelo desgaste. Não há faixas nos cruzamentos.
- **Cavernas.**
  - **Túneis sinuosos**, onde dois ruídos 3D passam juntos por zero (a técnica dos túneis "espaguete"), com ~3–4 m de raio, mais horizontais que verticais.
  - **Salões** em profundidade.
  - **Bocas de caverna** onde um ruído de entradas permite que os túneis cheguem à superfície. Fora delas, os túneis se fecham perto do chão para o terreno não virar queijo suíço.
  - Embaixo das estradas os túneis nunca abrem.
  - Leito de rocha a −40 m.
  - Cerca de 5,5% do subsolo é caverna.
- **Malha.** O campo é transformado em malha por *surface nets*: células de 2 m, um vértice por célula cortada e quadriláteros nas arestas. Cada pedaço gera uma borda de células a mais, então os vértices da divisa saem idênticos nos dois vizinhos. O teste confere que não há emenda.

### 3.2 Pedaços e desempenho (`scripts/world/procedural/procedural_world.gd`)

- **Tamanho.** Pedaços de 32 × 32 m, num raio de 4 pedaços em volta do jogador (cerca de 69 pedaços, ~144 m). No celular o raio é 3, e a neblina esconde a borda.
- **Geração.** Cada pedaço é gerado numa tarefa do `WorkerThreadPool`: densidade, malha, colisão e a lista de objetos. Leva ~40–50 ms por pedaço num núcleo de PC.
- **Montagem.** A linha principal só monta os nós, um pedaço por quadro, o mais perto primeiro. Não há engasgo ao andar.
- **Descarga.** Pedaços que ficam para trás são descarregados. Ao voltar, saem iguais, menos as armas que você já pegou.
- **Na partida,** os 9 pedaços em volta do ponto inicial são gerados antes do primeiro quadro. Você nasce em chão com colisão, na rodovia. Ao renascer longe, o chão é gerado na hora.
- **Desenho.**
  - Cada tipo de objeto vira uma instância múltipla (MultiMesh) por pedaço, com distância de desenho.
  - Colisões são caixas e cilindros simples; o chão usa a própria malha.
  - Os modelos da Poly Haven (até 100 mil triângulos) foram simplificados para 0,4–6 mil pelo próprio motor (`tools/build_world_assets.gd`), com níveis de detalhe.

### 3.3 O que aparece no mundo

- **Floresta de abetos** com densidade variável (mata fechada, clareiras e campos). Usa impostores com troncos reais e colisão nos troncos, samambaias, arbustos e galhos secos.
- **Natureza.** Pedras, tocos e troncos caídos. Paredões de rocha nas encostas e em volta das bocas de caverna.
- **Rodovias engarrafadas e abandonadas**, como nas fotos de referência:
  - trechos com carros, picapes, jipes, uma van, caminhões e ônibus enferrujados nas duas faixas, uns atravessados e outros caídos no barranco;
  - malas, sacos de lixo, galões, pneus, rodas soltas, latas, barris e caixotes pelo chão;
  - nas vicinais, carros esparsos e carros cobertos por lona.
- **Carcaças.** Os 13 veículos do "3D Vehicles Pack" (CC0) eram modelos de argila sem textura. Eles foram:
  - levados ao tamanho real, com escala por eixo porque eram estilizados;
  - amassados de leve;
  - divididos em lataria, vidros escuros e borracha dos pneus.

  O shader `wreck.gdshader` pinta cada carcaça com uma cor de fábrica desbotada (vermelho, azul, branco, verde-oliva, cinza, amarelo…). A ferrugem toma conta pelo desenho da textura de ferrugem, mais embaixo e no teto. Cor e quanto de ferrugem são sorteados por carcaça.
- **Armas pelo caminho.** De vez em quando há uma picareta, um machado ou um taco largado ao lado de um carro, ou perdido na mata.
- **Ambientação.**
  - Manhã encoberta com névoa entre as árvores: céu cinza-azulado e neblina densa, que dá profundidade e esconde a borda do mundo carregado.
  - Cores levemente dessaturadas.
  - Sombras do sol de manhã.

### 3.4 Cavernas: escuro de verdade e lanterna de cabeça

- **Sem iluminação global, a luz do céu iluminaria por igual o fundo de uma caverna.** Por isso:
  - o terreno guarda em cada vértice um fator de "céu aberto", que tira a luz difusa nas cavernas e deixa a rocha úmida e mais escura;
  - quando a câmera está sob a terra (`CaveAtmosphere`), a luz do céu, os reflexos, o sol e a cor da neblina caem até quase o escuro, numa transição de ~1,6 s (os olhos "se acostumando").
- **A lanterna de cabeça do sobrevivente acende sozinha.** É um foco com sombras, mais um halo fraco em volta. Fica na testa e aponta para onde você olha, então funciona em 1ª e 3ª pessoa. Na saída da caverna ela apaga.
- Paredes, tetos e barrancos usam rocha com musgo, projetada nos três eixos, sem esticar. O chão das cavernas é de cascalho e lama.

## 4. Controles novos

| Ação | Toque | Teclado/mouse | Controle |
|---|---|---|---|
| Pegar arma | USAR (mirando nela) | E | X |
| Soltar arma | SOLTAR (só aparece com arma) | G | direcional para baixo |
| Golpe rápido / carregado com arma | ATACAR (tocar / segurar) | botão esquerdo (clicar / segurar) | botão de ombro direito (tocar / segurar) |

## 5. Testes

| Bateria | Verificações | Godot 4.5.1 | Godot 4.7.1 |
|---|---|---|---|
| `tests/animation_tests.gd` | 307 | passam | passam |
| `tests/movement_tests.gd` | 119 | passam | passam |

Novas verificações:
- **Vento.**
  - Vento forte é ~15 dB mais alto que o fraco e tem o filtro 4× mais aberto.
  - Não há mais trilha nem pássaros.
  - Fôlego entre 12 e 42 respirações por minuto.
- **Armas.**
  - Tamanho e empunhadura das malhas.
  - Mirar mostra "Pegar …" e USAR pega do chão.
  - A arma fica presa à mão, na postura de arma, e o botão SOLTAR aparece.
  - Trocar deixa a anterior no chão; soltar volta à guarda de punhos.
  - As armas param no chão.
  - Cada arma acerta mais longe que o soco, com o dano dela.
  - O golpe carregado do machado segura a preparação e bate mais forte.
- **Mundo.**
  - Mesma semente gera o mesmo pedaço; outra semente gera outro.
  - Borda entre pedaços idêntica dos dois lados, e todas as faces viradas para o ar.
  - Tempo de geração por pedaço.
  - Cavernas: mais de 2% do subsolo, bocas abertas na superfície, leito de rocha.
  - Rodovia nivelada e sem cavernas sob o asfalto.
  - Carcaças ao longo de 1,3 km de rodovia, todas na pista ou no acostamento, e armas largadas.
  - Pedaços carregam em volta e descarregam atrás, e a memória fica limitada.
  - O jogador anda sobre a colisão gerada.
  - A arma de um pedaço aparece no chão.
  - A lanterna acende na caverna e apaga na superfície.
  - A cena principal começa com o jogador em pé na rodovia.

## 6. Arquivos

**Novos:**
- `scripts/world/wind.gd`: singleton do vento.
- `scripts/weapons/`:
  - `weapon_data.gd`
  - `weapon_pickup.gd`
  - `weapon_spawn.gd`
  - `player_equipment.gd`
- `scripts/world/procedural/`:
  - `world_generator.gd`
  - `procedural_world.gd`
  - `cave_atmosphere.gd`
  - `world_scene.gd`
- `scripts/world/tree_cards.gd`: impostores das árvores, usados pelos dois mapas.
- `resources/materials/world_terrain.gdshader` (+ `.tres`) e `wreck.gdshader`.
- `resources/weapons/*.tres`, `resources/models/weapons/`, `resources/models/world/`.
- `scenes/world/mundo.tscn`: cena principal.
- `tools/`:
  - `build_weapons.gd`
  - `build_world_assets.gd`
  - `build_world_scene.gd`
  - `mesh_tools.gd`
- `assets/weapons/pickaxe/`, `assets/vehicles/` e 13 itens novos da Poly Haven.

**Modificados:**
- `scripts/player/melee_combat.gd`: golpes, alcance e dano da arma.
- `scripts/player/interaction_component.gd`: pega objetos físicos e contato tolerante.
- `scripts/animation/body_animator.gd`: postura de guarda trocável.
- `scripts/audio/player_sounds.gd`: fôlego por respirações avulsas e sons das armas.
- `scripts/world/scatter_instances.gd`: cor por instância.
- `scenes/player/player.tscn`: nó `Equipment`.
- `scenes/ui/touch_controls.tscn`: botão SOLTAR.
- `tools/retarget_animations.gd`: golpes de arma, pose congelada e quadro de impacto.
- `tools/prepare_audio.py`, `tools/build_demo_map.gd`, `tools/download_polyhaven.py`.
- `project.godot`: cena principal, `Wind`, ação `drop_weapon` e parâmetro global do vento.
- `export_presets.cfg`: os modelos-fonte usados só para gerar as malhas ficam fora do APK.

**Removidos:**
- `scripts/audio/ambience.gd`
- `assets/audio/ambience/floresta.ogg`
- `assets/audio/ambience/passaros.ogg`

## 7. Limitações honestas

- **Desempenho no celular.**
  - O mundo foi pensado para o Android: pedaços em segundo plano, MultiMesh, malhas simplificadas, raio menor no celular e neblina.
  - Mas é bem mais pesado que o mapa fixo, e só um aparelho real confirma.
  - Se travar, os ajustes são `view_distance` e `max_tasks` no nó `ProceduralWorld` da cena `mundo.tscn`, e a distância de desenho das árvores.
- **Muito longe da origem.** O mundo é infinito na prática, até milhares de km. Muito longe da origem a precisão dos números de ponto flutuante começa a tremer a imagem; o normal de quem joga não chega lá.
- **Carcaças.** Os veículos gratuitos são modelos estilizados de argila. A pintura, a ferrugem, os vidros e o tamanho real os aproximam das fotos, mas não têm interior nem portas abertas.
- **Sem zumbis ainda.** O mundo, as estradas e as cavernas estão prontos para recebê-los na etapa dos zumbis.
- **As armas não se desgastam e não há inventário.** Você carrega uma arma por vez, na mão. O inventário é uma etapa futura.
- **Sons sem audição humana.** Escolhi e ajustei os sons pelos dados (duração, volume, espectro), mas não posso ouvi-los. O fôlego e o vento são fáceis de ajustar em `player_sounds.gd` e `wind.gd`.
