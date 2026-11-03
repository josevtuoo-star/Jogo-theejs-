# Etapa 9 — Menu, mundos, bancada, biomas e cidades

Pedido do dono do projeto (com capturas de tela e imagens de referência):

- pedras com textura "bugada" e pedaços flutuando nas encostas;
- o personagem não conseguia subir os morros: subir com as mãos no chão;
- árvores piscando ao andar rápido;
- não achou as cavernas nem as ferramentas;
- menu inicial, mundos com semente própria (aleatória ou digitada), salvos na
  memória do celular com permissão, personagem personalizável;
- inventário e bancada como na imagem de referência (grade, armadura,
  bancada 2 × 2); sistema de fabricar; mais ferramentas;
- quebrar árvore com a mão (demorando mais);
- mais vegetação, relevo e biomas, cada um com a sua vegetação;
- vilas, cidades pequenas e grandes pós-apocalipse;
- zumbis variados, no estilo de série de zumbis.

## 1. Diagnóstico e correções

### 1.1 Pedras "bugadas" e flutuando

As duas capturas mostram o mesmo modelo: `rock_face_01` (Poly Haven), que é
uma **fatia de penhasco escaneada, com as laterais cortadas retas** — visto de
lado parece uma caixa com textura esticada. O gerador o colocava em encostas
íngremes com a base no ponto do centro: num declive de 50–65° o lado de baixo
ficava no ar (as "lascas" flutuando da segunda captura).

Correção: o scan saiu do jogo (e do repositório). No lugar, **rochedos
procedurais** (`rochedo_0..2`, `tools/build_world_assets.gd`): blocos
arredondados e irregulares, textura de rocha **projetada nos três eixos** (não
estica em nenhum ângulo), musgo no que fica virado para cima, colisão pelo
**casco convexo** da própria malha. Tudo o que é espalhado no chão (rochedos,
pedras, tocos, troncos) agora é assentado pelo **ponto mais baixo do chão
sob o objeto** (`seat_height`): numa encosta, o lado de cima fica enterrado e
nada flutua.

### 1.2 Árvores piscando em movimento

As árvores são impostores: três planos cruzados com a foto do modelo. Ao
passar rente a uma árvore (ou por dentro da copa), o plano mais próximo
aparecia enorme, listrado e visto de lado, e cada plano visto de quina virava
uma faixa esticada que piscava a cada quadro. Correção no shader
(`tree_card.gdshader`): o plano visto de lado e o plano colado na câmera
somem num pontilhado fixo na tela (sem ruído no tempo), e o recorte das
bordas usa alfa para cobertura (MSAA). Diferença média entre quadros andando
a 7 m/s: 16,7 → 12,7.

### 1.3 Não achou as cavernas nem as ferramentas

- Mundo novo começa com um **acampamento abandonado** ao lado da estrada:
  picareta, machado de bombeiro e duas tochas no chão.
- **Bússola da caverna** no alto da tela: seta e distância até a boca de
  caverna mais próxima (até 250 m). A caverna da partida é garantida
  (~60 m da estrada).

## 2. Escalada de encostas (mãos no chão)

Entre a inclinação caminhável (46°) e 70°, empurrando morro acima, o
sobrevivente **escala**: sobe devagar (~1 m/s) apoiando as mãos, sem o
"escorrega" de antes. Soltar o comando = escorrega de volta; acima de 70° é
parede. A quina de um degrau não é confundida com encosta (um raio de cima
confirma o piso inclinado), e ao chegar ao topo ele passa a borda.

Animação: base agachada no ritmo dos passos, tronco dobrado para a encosta e
**IK das duas mãos** com alvos achados por raios contra o chão de verdade: a
mão que avança sobe um pouco da rocha e é plantada adiante, a outra empurra.
O olhar para cima não joga o tronco para trás.

## 3. Menu inicial e mundos

- **Fundo 3D**: a própria rodovia abandonada na neblina, com a câmera
  passando devagar.
- **CONTINUAR** (último mundo), **NOVO MUNDO** (nome e semente: número ou
  palavra; vazio = sorteada; SORTEAR), **CARREGAR MUNDO** (lista com JOGAR e
  APAGAR com confirmação), **PERSONAGEM**, **SAIR**.
- **Semente**: a mesma semente gera sempre o mesmo mundo (relevo, cavernas,
  estradas, biomas, cidades). O nome e a semente aparecem no menu de pausa.
- **Salvamento** (`GameSession`): mundos em `user://mundos/<id>/mundo.json`
  — no Android, a pasta privada do aplicativo na memória interna. Grava a
  posição, a vida, a mochila (com armadura e durabilidade), as árvores
  cortadas, o minério colhido, os zumbis mortos e as armas pegas. Salva
  sozinho a cada minuto, ao sair para o menu e quando o celular põe o jogo
  em segundo plano.
- **Permissão**: na primeira vez o jogo pergunta se pode salvar os mundos na
  memória do celular (PERMITIR / AGORA NÃO). Sem permissão joga-se
  normalmente, sem gravar nada; dá para permitir depois pelo menu. A pasta
  privada do aplicativo não exige permissão do sistema Android (a de
  "armazenamento" vale só para pastas públicas e não é usada).
- **Menu de pausa** (P / Start / botão MENU): CONTINUAR, SALVAR, SAIR PARA O
  MENU.

## 4. Personagem

PERSONAGEM no menu: cor da jaqueta (8), calça (6), botas (4), gorro (6),
pele (5) e cabelo/barba (6), com o sobrevivente em 3D girando (arrastar gira
à mão). Vale para o corpo no jogo e para o retrato da mochila.

## 5. Mochila em grade e bancada (como a referência)

- **Casas**: barra rápida de 9 (embaixo, tocável), mochila de 27 (3 × 9),
  armadura (cabeça, tronco, pernas, pés) ao lado do **retrato 3D** do
  sobrevivente com o que está vestido, e a **BANCADA 2 × 2** com seta e
  resultado.
- **Toque**: toque num item e depois em outra casa para mover, trocar ou
  juntar pilhas; numa casa da bancada vai uma unidade por toque; tocar no
  resultado fabrica. À direita: o item escolhido (para que serve,
  durabilidade, NA MÃO / GUARDAR / VESTIR / TIRAR / PARA A BARRA / SOLTAR 1 /
  SOLTAR) e a lista de **RECEITAS** (FABRICAR com um toque, com o que falta
  em vermelho). Fechar devolve o que ficou na bancada.
- **Receitas** (16, cada uma com uma combinação própria; a posição na
  bancada não importa):

| Resultado | Ingredientes |
|---|---|
| 4 tábuas | 1 madeira |
| 4 gravetos | 2 tábuas |
| 2 tochas | 1 graveto + 1 carvão |
| Faca de pedra | 1 pedra + 1 graveto |
| Machado de pedra | 2 pedras + 1 graveto |
| Picareta de pedra | 2 pedras + 2 gravetos |
| Lança | 3 gravetos + 1 pedra |
| Taco com pregos | 2 tábuas + 1 ferro |
| Facão | 2 ferros + 1 tábua |
| Machado de bombeiro | 2 ferros + 1 graveto |
| Picareta | 2 ferros + 2 gravetos |
| Pé de cabra | 3 ferros + 1 carvão |
| Capacete de sucata | 3 ferros |
| Colete de chapas | 4 ferros |
| Joelheiras | 1 ferro + 1 tábua |
| Botas reforçadas | 2 ferros + 1 carvão |

## 6. Ferramentas, armaduras e mãos nuas

- **Novas**: machado de pedra, picareta de pedra, faca de pedra (a mais
  rápida), lança (alcance de 1,2 m), tocha (luz quente que tremula, chama e
  fagulhas; queima com o tempo na mão), facão e pé de cabra (modelos Poly
  Haven, CC0). As de pedra, a lança e a tocha são geradas
  (`tools/build_weapons.gd`): cabo de galho com casca, pedra lascada e
  amarração de corda.
- **Rendimento** por tipo e nível: árvore — mãos < machado de pedra / facão
  < machado de bombeiro; rocha — picareta de pedra serve para pedra e
  carvão, **ferro pede picareta de metal** (aviso na tela).
- **Árvore a socos**: as mãos nuas derrubam árvores, bem mais devagar (no
  teste: 28 socos contra ~6 golpes do machado de bombeiro).
- **Armaduras** de sucata: capacete (15%), colete (25%), joelheiras (8%),
  botas reforçadas (6%) do dano absorvido; quedas não são absorvidas; cada
  golpe absorvido gasta as peças. Aparecem no corpo, presas aos ossos (em
  primeira pessoa o capacete só faz sombra).

## 7. Biomas

Temperatura e umidade variam devagar pelo mundo, e a altitude esfria:

| Bioma | Chão | Árvores | Plantas |
|---|---|---|---|
| Coníferas (o da partida) | chão de floresta | abetos | samambaias, arbustos |
| Folhosas | folhas secas | árvore de folhas largas | arbustos, samambaias |
| Campo | capim | poucas árvores | mato e arbustos em toda parte |
| Seco | terra pedregosa | árvores mortas e árvores-aljava | galhos secos |
| Neve | neve (também nas encostas) | abetos e árvores secas | quase nada |

As árvores novas são impostores como os abetos: atlas de
`tools/bake_broadleaf_impostors.gd` a partir de modelos de milhões de
polígonos da Poly Haven (ficam fora do jogo). O terreno recebe os pesos dos
biomas por vértice (canal `CUSTOM0`) e o shader troca o chão com transição
suave.

## 8. Vilas e cidades

Uma região de 448 m pode ter uma **vila** (5–9 casas de um ou dois andares,
telhado de duas águas, tijolo, reboco ou tábuas, terra batida em volta) ou
uma **cidade** (quarteirões de 46 m numa grade de ruas asfaltadas com
calçadas, prédios de 2 a 8 andares de tijolo, reboco ou concreto, mais altos
no centro). Ficam junto da rodovia quando ela passa, num **platô aplainado**
(corte e aterro em volta), nunca a menos de ~230 m da partida nem em relevo
acidentado. Cada uma tem nome (ex.: "Rio Claro", "Vila Serra Azul").

Abandono pós-apocalipse (no shader das fachadas, sem custo de geometria):
janelas de vidro sujo, quebradas ou tapadas com tábuas; portas arrombadas;
vitrines no térreo; escorridos de sujeira, base encardida, **trepadeiras
subindo pelas paredes** e musgo nos telhados. Nas ruas: carcaças, postes
apagados, lixeiras, barris, caixotes, pneus e mato; **zumbis** (mais nas
cidades); armas, **sucata de ferro** e tábuas para pegar. Os prédios são
sólidos (colisão); ainda não dá para entrar (etapa 10).

## 9. Zumbis variados

Cinco roupas de quem eles eram — policial, operário (colete laranja e
capacete), civil (camisa e jeans), esfarrapado e sem camisa (magro) — com
pele em tons de decomposição, sangue seco e encardido (cores por vértice na
pose de repouso: as manchas não escorregam com a animação), veias na pele,
altura e magreza diferentes, **postura própria** (cabeça caída, tronco
curvado, um braço pendurado) e passo próprio. A roupa sai da chave do
zumbi: ao recarregar o pedaço ele volta igual.

## 10. Testes

| Bateria | Verificações | Godot 4.5.1 | Godot 4.7.1 |
|---|---|---|---|
| `tests/animation_tests.gd` | 454 | passam | passam |
| `tests/movement_tests.gd` | 126 | passam | passam |

Novos nesta etapa: escalada (55° e 62° sobem, 76° não, soltar escorrega,
degraus continuam sendo degraus, mãos tocando a encosta), bancada (grade,
resultado, receitas, devolução), armadura (absorção, desgaste, visual,
tirar), rendimento das ferramentas, árvore a socos, tocha, sementes e
salvamento (gravar, listar, carregar, apagar), menu (botões, permissão,
personagem), biomas, vilas e cidades (platô, prédios sólidos, ruas) e
variedade de zumbis.

## 11. Arquivos

Novos:
- `scripts/autoload/game_session.gd` (mundo aberto, semente, salvamento, permissão, aparência)
- `scripts/ui/main_menu.gd`, `scripts/ui/menu_style.gd`, `scripts/ui/pause_menu.gd`, `scripts/ui/cave_compass.gd`,
  `scripts/ui/character_preview.gd`, `scripts/ui/inventory_slot_view.gd`, `scenes/menu/menu_principal.tscn`
- `scripts/inventory/crafting.gd`, `scripts/inventory/armor_visuals.gd`, `scripts/player/character_look.gd`
- `scripts/npc/zombie_look.gd`, `scripts/npc/zombie_posture.gd`, `resources/materials/zombie.gdshader`
- `resources/materials/building.gdshader` (+ `.tres`), `tools/bake_broadleaf_impostors.gd` (+ `.tscn`),
  `resources/textures/trees/broadleaf_cards.png`
- itens, ícones e malhas novos (ferramentas, tábua, graveto, armaduras, rochedos, plantas, poste, lixeira)

Modificados:
- `scripts/inventory/inventory.gd` (casas), `item_data.gd`, `item_pickup.gd`, `scripts/ui/inventory_hud.gd`,
  `hotbar_touch_slot.gd`, `scenes/ui/touch_controls.tscn` (9 casas, MENU)
- `scripts/player/player_controller.gd` e `movement_settings.gd` (escalada), `scripts/animation/body_animator.gd` (pose de escalada)
- `scripts/components/health_component.gd` (armadura), `scripts/weapons/player_equipment.gd` (tocha)
- `scripts/world/procedural/world_generator.gd` (biomas, vilas e cidades, rochedos assentados),
  `procedural_world.gd`, `chunk_resources.gd` (rendimento por ferramenta, mãos), `world_scene.gd` (sessão, kit, salvar)
- `scripts/world/tree_cards.gd`, `resources/materials/tree_card.gdshader`, `world_terrain.gdshader` (+ `.tres`),
  `cave_rock.gdshader`
- `scripts/npc/zombie.gd`, `scripts/player/melee_combat.gd`
- ferramentas em `tools/`, `project.godot` (cena inicial, `GameSession`, teclas 5–9 e P), `export_presets.cfg`

## 12. Limitações honestas

- Prédios ainda não têm interior (portas e janelas são desenhadas na
  fachada); entrar e construir é a etapa 10.
- Os zumbis andam em linha reta até o jogador (sem rotas): podem esbarrar
  em prédios e carcaças.
- Gerar um pedaço passou de ~46 ms para ~65 ms (biomas e povoados), em
  segundo plano; falta medir no aparelho.
- A personalização troca cores das partes do modelo atual (não há outros
  cortes de roupa nem outros rostos).
- Os mundos antigos da etapa 8 não existiam como "mundos salvos": a semente
  padrão continua gerando o mesmo relevo, mas agora com biomas e povoados.
