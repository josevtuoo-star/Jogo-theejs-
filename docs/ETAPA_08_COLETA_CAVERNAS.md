# Etapa 8 — Lanterna, cavernas exploráveis, mochila, coleta e zumbis

Pedidos do dono do projeto (03/11/2026), em dois blocos:

1. **Refinamento do mapa e correção visual:**
   - preservar o mapa aprovado;
   - investigar e corrigir na origem a sombra artificial da lanterna;
   - refazer o visual das cavernas (rocha natural, entradas, transições, texturas, luz).
2. **Ferramentas, coleta e exploração:**
   - pegar ferramentas (botão PEGAR) e guardá-las numa mochila com ícones e durabilidade;
   - cortar árvores com o machado e minerar com a picareta (inspirado no Minecraft, com física e animação realistas);
   - lutar contra zumbis com o taco, que tem durabilidade e quebra;
   - cavernas que dá para explorar de verdade, entrando e saindo livremente.

Preservado:
- o relevo, as estradas, a floresta, as carcaças e os destroços (os ruídos do relevo não mudaram; só as cavernas foram trocadas);
- o personagem e as animações existentes;
- a movimentação (nenhum parâmetro de física do jogador mudou);
- as câmeras de 1ª e 3ª pessoa;
- os controles de toque (golpe só pelo botão ATACAR);
- as otimizações (pedaços em segundo plano, MultiMesh, raio menor no celular).

## 1. Diagnóstico

### 1.1 Lanterna: a sombra na frente do jogador

Reproduzido em renderizações dentro da caverna: olhando o chão, uma silhueta escura enorme do próprio corpo cobria o foco; olhando o teto, quase tudo preto; um ponto branco estourado na borda inferior. Investigação:

| Verificado | Encontrado |
|---|---|
| Posição da SpotLight3D | 25 cm à frente dos olhos **na direção da câmera**. Olhando para baixo, ela descia para dentro do peito; para cima, entrava no gorro. |
| Direção do cone | Correta (segue a câmera). |
| Distância câmera–luz | Variava com a inclinação da câmera (é o problema acima). |
| Sombra do próprio corpo | **Origem principal.** As malhas do jogador estavam na mesma camada do mundo; em 1ª pessoa o corpo inteiro fica no modo "só sombra" (para a sombra do sol) e tapava a lanterna. |
| Shadow bias / normal bias | 0,03 / 1,0 (padrão): acne leve na rocha de células de 2 m vista de raspão. |
| Resolução do mapa de sombras | Atlas de sombras pontuais: 4096 no PC, 2048 no celular. Suficiente para um único foco. |
| Clipping perto da câmera | O ponto branco: partes do corpo a centímetros da luz, superexpostas pelo inverso do quadrado da distância. |
| Geometria bloqueando a luz | A própria cabeça e o tronco (sombra só-sombra). |
| Interferência entre luzes | O halo era uma luz pontual sem sombra 0,9 m à frente: perto da parede entrava na rocha e iluminava o outro lado. |

### 1.2 Cavernas

Medido no gerador antigo (túneis "espaguete" de ruído 3D):
- 26% do chão das cavernas tinha mais de 40° de inclinação (o personagem sobe no máximo 46°);
- 9% dos pontos tinham menos de 2 m de altura livre;
- 24% das bocas eram poços verticais de mais de 4 m (quem caía não saía).

Eram tubos sem chão, sem saída garantida e com aparência artificial.

Durante a reforma, os testes andando com a física encontraram e corrigiram mais quatro problemas:
- a rugosidade da rocha era calculada pelo chão da galeria, não pelo da rampa, e criava calombos íngremes no piso das rampas;
- o chão plano estreito virava um "V" de faces íngremes na malha de 2 m;
- a rugosidade às vezes baixava o teto abaixo da altura do personagem;
- havia degraus entre o fim da rampa e a galeria.

## 2. Correções

### 2.1 Lanterna (`scripts/world/procedural/cave_atmosphere.gd`)

- **Na testa:** ponto fixo 7 cm acima e 11 cm à frente dos olhos, pelo referencial horizontal do corpo (não acompanha a inclinação da câmera), apontada para onde se olha. Funciona igual em 1ª e 3ª pessoa: em 3ª pessoa a luz sai da testa do personagem, não da câmera.
- **O corpo não sombreia nem estoura a própria lanterna.** As malhas do sobrevivente e a ferramenta na mão ficam numa camada própria; o foco a exclui das sombras (`shadow_caster_mask`) e da luz (`light_cull_mask`). Uma luz suave só para o jogador ilumina mãos e ferramenta por igual. O sol continua desenhando a sombra do corpo.
- **As sombras do mundo continuam:** o foco projeta sombra das rochas, formações e objetos, com viés ajustado para a rocha (bias 0,06, normal 1,6, suavização 1,5).
- **Halo:** um segundo foco largo, sem sombra, saindo do mesmo ponto (não entra mais nas paredes).
- **Desempenho:** um único mapa de sombras. Embaixo da terra o sol fica fraco e as sombras dele se desligam quando a luz dele chega a quase zero.

### 2.2 Cavernas (`scripts/world/procedural/world_generator.gd`)

- **Galerias:** num nível subterrâneo (~14 m abaixo do nível de referência, variando ±4 m devagar). Seguem as linhas de zero de dois ruídos 2D; essas linhas não terminam, então não há beco sem saída por erro de construção, e onde as duas famílias se cruzam há bifurcações.
- **Corte transversal natural:**
  - chão quase plano que sobe junto às paredes e teto em arco;
  - largura e altura variam: corredores de ~6 m, câmaras de até 16 m de largura e 7 m de altura;
  - a rocha irregular só escava (alarga paredes, sobe o teto) e nunca estreita a passagem.
- **Entradas:** rampas inclinadas (10° a 21°) da superfície até uma galeria.
  - Começam como uma fenda que corta o terreno e viram túnel; a boca é mais larga e alta, com paredões de rocha dos lados.
  - Desviam das estradas e não cruzam outras galerias no caminho.
  - Chegam ao nível da galeria aos 80% e seguem planas, sem degrau na volta.
  - Uma a cada região de 160 m, com chance; a mais próxima do ponto de partida é garantida (fica a ~67 m).
- **Sem buracos:** o chão das galerias fica ao menos 12 m abaixo da superfície; a única ligação com o exterior são as rampas.
- **Formações e minério:**
  - estalagmites e estalactites (geometria procedural, com anéis de crescimento);
  - entulho;
  - blocos de carvão e de ferro junto às paredes, com veios.

  O meio da galeria fica livre para passar.
- **Colisões:**
  - a colisão do terreno é a própria malha visível;
  - estalagmites têm colisão cilíndrica fina;
  - entulho miúdo não colide (antes, caixas de colisão maiores que a pedra viravam paredes invisíveis).
- **Rede de segurança:** se algo jogar o jogador ou um item para dentro da rocha (o terreno é uma casca), ele volta ao último ponto seguro.

### 2.3 Visual e luz das cavernas

- **Texturas** (`world_terrain.gdshader`):
  - rocha cinza (o "Mossy Rock" sem o verde do musgo) com estratos alaranjados que ondulam (Cliff Side);
  - manchas escuras e lisas de umidade, variando pelo mundo, sem repetição;
  - chão de cascalho com pedras (Brown Mud Rocks).
- **Luz que entra pelas aberturas:** cada vértice do terreno guarda quanto céu se enxerga dali, medido com 13 raios no campo de densidade (para cima, inclinados e rasantes). A luz difusa entra pela boca, avança alguns metros pelo túnel e some aos poucos (o teste mede 31% de escuro na boca e 100% no fundo). Nunca fica preto absoluto: resta uma luz rebatida fraca.
- **Câmera:** sob a terra, a luz geral e o sol baixam e os olhos "se acostumam" (exposição) em ~1,6 s. O céu não escurece: de dentro, a boca da caverna continua clara.

## 3. Mochila, PEGAR e barra rápida

- **Itens** (`resources/items/*.tres`, classe `ItemData`): machado, picareta, taco (ferramentas) e madeira, pedra, carvão e minério de ferro (recursos). Os ícones são desenhados a partir dos modelos 3D do próprio jogo (`tools/build_items.gd`).
- **PEGAR:**
  - Ao mirar num item ao alcance, aparece um cartão com o ícone e o nome, e o botão de toque USAR vira **PEGAR**.
  - O item some do chão e entra na mochila, com um aviso "+N nome" e o ícone.
  - O mesmo objeto não entra duas vezes (o item é desligado no instante em que é pego).
  - Itens pequenos (pedras) são fáceis de pegar: a mira procura em volta do ponto mirado.
  - O alcance passou de 2,0 m para 2,3 m dos olhos (pegar algo no chão à frente dos pés).
- **Mochila** (`Inventory`):
  - 4 casas de ferramentas (cada uma com sua durabilidade) e recursos empilhados;
  - pegar uma ferramenta com as mãos livres já a empunha.
- **Barra rápida:** 4 casas embaixo, com ícone, número e barra de durabilidade; a da mão fica destacada.
  - Teclado: 1–4 empunha (de novo = guarda); G solta.
  - Controle: setas esquerda/direita trocam; seta para baixo solta.
  - Toque: as casas são botões do roteador multitoque, então um dedo ali nunca gira a câmera nem golpeia; SOLTAR aparece com ferramenta na mão.
- **Painel MOCHILA** (I / Tab / Y / botão MOCHILA):
  - ferramentas com durabilidade (EMPUNHAR, GUARDAR, SOLTAR);
  - recursos com quantidade (SOLTAR 1);
  - ORGANIZAR.

  Com o painel aberto o personagem para e os controles de toque somem.
- **Soltar:** o item cai à frente sobre o chão encontrado por um raio (nunca dentro do terreno); se a frente estiver bloqueada, cai aos pés.

## 4. Machado: corte de árvores

- Cada árvore tem resistência própria, pela variedade e pelo tamanho (abetos de 6 a 19 m: ~3 a ~8 golpes).
- Só o machado corta, e é preciso dar o golpe. Com outra ferramenta ou a mão, o golpe rebate e um aviso diz que precisa de machado.
- Diante de uma árvore, o golpe do machado é o de lenhador: um ciclo do TreeChopping, que sai com o machado erguido atrás e desce até a cintura, com o impacto aos 0,2 s.
- Cada golpe:
  - tira resistência e solta lascas;
  - toca o som de madeira e faz a copa e o tronco balançarem;
  - gasta o machado.
- Esgotada, a árvore racha (som) e **tomba como corpo físico**, empurrada para o lado oposto ao golpe, girando sobre a base. Fica um toco.
- Depois de cair, o tronco se parte em 3 a 7 **toras de madeira**, conforme o tamanho; cada tora se pega com PEGAR.
- A árvore cortada não volta ao recarregar o pedaço.

## 5. Picareta: mineração

- **Depósitos:**
  - pedra: as rochas soltas da superfície e o entulho das cavernas;
  - carvão e minério de ferro: dentro das cavernas.

  Cada um tem resistência própria pelo tipo e pelo tamanho (pedra < carvão < ferro).
- Só a picareta minera. Diante da rocha, o golpe é de cima para baixo: o primeiro golpe do Sword_Attack, congelado antes da segunda estocada, com o impacto aos 0,43 s.
- Cada golpe solta pó e lascas na cor do mineral e soa pedra.
- **Ao quebrar**, solta os recursos:
  - pedra: 3 a 4 pedras;
  - carvão: 2 a 3 carvões e 1 pedra;
  - ferro: 2 a 3 minérios de ferro e 1 pedra.

  O depósito quebrado não volta.
- Para novos minérios: uma linha em `ChunkResources.DEPOSIT_HEALTH` e `DEPOSIT_YIELD`, um item em `tools/build_items.gd` e o material em `tools/build_world_assets.gd`.

## 6. Taco e zumbis

- **Zumbi** (`scripts/npc/zombie.gd`):
  - mesmo corpo do sobrevivente, com a pele pálida esverdeada e a roupa encardida;
  - animações de zumbi (Quaternius UAL2, CC0) retargetadas;
  - vaga devagar; percebe o jogador pela visão (22 m, à frente, sem rocha no caminho) ou pelo barulho (perto ou correndo) e persegue no passo arrastado, com a passada sincronizada à velocidade;
  - ataca com o arranhão; o dano (12) sai no quadro em que a mão passa à frente, só se o jogador ainda estiver ao alcance.
- **Ao apanhar:**
  - perde vida e recua pelo impulso do golpe (~30 cm com o taco);
  - cambaleia (impacto leve ou forte), solta sangue e geme.
- **Morte:** vira ragdoll empurrado na direção do golpe final.
- **No mundo:** entre as carcaças dos engarrafamentos e, raros, na mata; nunca a menos de 45 m da partida. Os mortos não voltam.
- **Durabilidade:** taco 60 golpes, machado e picareta 140. Cada golpe útil gasta 1; ao chegar a zero, a ferramenta quebra, some da mão e da mochila e um aviso diz qual quebrou.
- **Golpe só pelo botão ATACAR:** arrastar o dedo para girar a câmera nunca golpeia (testes reais de toque), e tocar na barra rápida também não.

## 7. Testes

| Bateria | Verificações | Godot 4.5.1 | Godot 4.7.1 |
|---|---|---|---|
| `tests/animation_tests.gd` | 391 | passam | passam |
| `tests/movement_tests.gd` | 119 | passam | passam |

Todos com o jogo de verdade: física do personagem, animações, entrada por ações e eventos de toque reais.

**Lanterna**

| Situação | O que o teste verifica |
|---|---|
| Ambiente aberto | apagada de dia |
| Dentro da caverna | acende |
| Na boca | escurece aos poucos |
| Perto da parede | a luz não entra na rocha |
| Apontando para o chão e para o teto | o foco segue a mira e a lanterna fica na testa |
| Câmera em movimento | o foco acompanha |
| 1ª e 3ª pessoa | em 3ª pessoa a luz sai da testa, não da câmera |
| Configuração | corpo fora das sombras e da luz do foco; um único mapa de sombras |

**Cavernas**

| Situação | O que o teste verifica |
|---|---|
| Entrada e saída | em 2 cavernas: desce a rampa andando até 21 e 26 m sob a superfície, depois sai ao ar livre |
| Interior | corre 12 m pela galeria e agacha |
| Mineração dentro | quebra carvão e o coleta |
| Geometria | 0% de chão acima de 40°; 0% com altura abaixo de 2,1 m; 12 rampas com o trecho mais íngreme a 20°; nenhum buraco fora das rampas |
| Colisões | o jogador anda sobre a colisão gerada; nenhuma parede invisível no caminho |
| Desempenho | ~45 ms por pedaço em segundo plano |

**Ferramentas e coleta**
- Pegar: machado e picareta, com nome e ícone, o botão PEGAR e o cartão; não pega duas vezes; recursos empilham.
- Empunhar e guardar: pela tecla 1–4 e pelo toque na barra.
- Soltar: ferramentas e recursos; também pelo painel e pelo botão MOCHILA, sem golpes acidentais.
- Cortar uma árvore: taco não corta e avisa; o machado tira resistência e se desgasta; a árvore cede em 6 golpes, tomba como corpo físico e vira 6 toras; coletar madeira.
- Minerar uma rocha: o golpe de picareta; quebra em 7 golpes e solta 3 pedras; coletar pedras.
- Atacar um zumbi: ele persegue e fere; o taco o fere, ele recua e cambaleia, o taco se desgasta; morre em 5 golpes e vira ragdoll.
- O taco gasto quebra no golpe.

## 8. Arquivos

**Novos**

| Área | Arquivos |
|---|---|
| Mochila | `scripts/inventory/item_data.gd`, `inventory.gd`, `item_pickup.gd` |
| Interface | `scripts/ui/inventory_hud.gd`, `hotbar_touch_slot.gd` |
| Recursos e efeitos | `scripts/world/procedural/chunk_resources.gd`, `scripts/world/impact_effects.gd` |
| Zumbi | `scripts/npc/zombie.gd` |
| Materiais | `resources/materials/cave_rock.gdshader` |
| Itens e ícones | `resources/items/*.tres`, `resources/icons/*.png` |
| Malhas geradas | `resources/models/world/` (estalagmite, estalactite, minérios, pedaços, tora) |
| Ferramentas | `tools/build_items.gd` |
| Texturas | `assets/polyhaven/textures/cliff_side`, `brown_mud_rocks_01` |
| Sons | 26 sons novos em `assets/audio/world` e `assets/audio/voice` |

**Modificados**

| Arquivo | Mudança |
|---|---|
| `scripts/world/procedural/cave_atmosphere.gd` | lanterna na testa, camadas, halo, luz pela visibilidade do céu |
| `scripts/world/procedural/world_generator.gd` | galerias, rampas, luz por raios, formações, minério, zumbis, lista de árvores |
| `scripts/world/procedural/procedural_world.gd` | árvores e depósitos coletáveis, zumbis, o que foi colhido não volta |
| `scripts/world/procedural/world_scene.gd` | rede de segurança |
| `resources/materials/world_terrain.gdshader` / `.tres` | rocha e chão de caverna, luz difusa pelo céu visível |
| `scripts/player/melee_combat.gd` | forma atingida, golpe recusado rebate, desgaste, golpes de trabalho |
| `scripts/player/interaction_component.gd` | foco solto, procura em volta, alcance 2,3 m |
| `scripts/weapons/player_equipment.gd`, `weapon_pickup.gd` | mão = casa da mochila; durabilidade; rede de segurança |
| `scripts/ui/player_hud.gd` | PEGAR |
| `scenes/player/player.tscn` | nó Inventory |
| `scenes/ui/touch_controls.tscn` | barra rápida e MOCHILA |
| `tools/build_world_scene.gd`, `build_demo_map.gd`, `build_test_gym.gd` | HUD da mochila |
| `tools/retarget_animations.gd` | corte, mineração, zumbis |
| `tools/build_world_assets.gd` | malhas e materiais procedurais |
| `tools/prepare_audio.py` | sons de coleta e de zumbi |
| `tools/setup_input_map.gd` | 1–4, setas, I/Tab/Y |
| `tools/download_polyhaven.py` | texturas novas |
| `project.godot` | ações novas |

## 9. Limitações honestas

- **Desempenho no celular:**
  - cada pedaço agora tem também árvores e depósitos com colisão própria, e até 2 zumbis animados;
  - a geração por pedaço subiu de ~36 para ~45 ms no PC, em segundo plano;
  - a confirmação só vem de um aparelho real. Se pesar, os ajustes são o raio do mundo e a chance de zumbis (`WorldGenerator`).
- **Zumbis simples:**
  - andam em linha reta até o jogador, sem navegação por caminhos: um barranco ou uma carcaça os segura;
  - não entram nas cavernas por conta própria;
  - não abrem portas (não há portas ainda).
- **Árvores do mapa fixo** (`demo_forest.tscn`): continuam decorativas. O corte é do mundo procedural.
- **A rocha das cavernas não se escava** (o terreno não é editável): a picareta minera os depósitos, não as paredes.
- **Sons sem audição humana:** escolhidos e ajustados pelos dados; fáceis de trocar em `tools/prepare_audio.py`.
