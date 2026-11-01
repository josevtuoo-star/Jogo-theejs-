# Etapa 5 — Correção profunda da jogabilidade

O mapa da etapa 4 foi preservado sem alterações: terreno, árvores, vegetação, posto militar e iluminação. Esta etapa trata do personagem, das animações, da física, do combate e dos controles de toque.

## 1. Bug grave: soco ao arrastar o dedo para girar a câmera

### Causa (origem, não sintoma)

Dois fatores juntos:

1. A ação `attack` estava ligada ao **botão esquerdo do mouse de qualquer dispositivo** (`device = -1` no InputMap).
2. O Godot, por padrão, **emula cliques de mouse a partir do toque** (`emulate_mouse_from_touch`). No Android, todo dedo que encostava na tela gerava também um clique esquerdo emulado. Ao soltar o dedo, o `MeleeCombat` via "apertou e soltou o ataque" e dava um soco rápido.

Os controles de tela tratavam os eventos de toque corretamente. O problema vinha do evento de mouse emulado, que é um evento separado.

O teste de reprodução, com o mesmo fluxo de eventos do Android, deu **1 soco por arrasto** antes da correção e **0** depois.

### Correção

- **InputMap** (`tools/setup_input_map.gd`): os botões do mouse das ações de jogo (`attack`, `block`, zoom) valem **só para o mouse físico** (dispositivo 0). Eventos emulados chegam com `InputEvent.DEVICE_ID_EMULATION` (−1) e não acionam nenhuma ação.
  - A emulação continua ligada, porque é por ela que os `Button` da interface, como RENASCER, recebem toques.
- **`GameInput`** ignora eventos de mouse emulados, então o toque não gira a câmera em dobro.
- **`TouchControls`** é o roteador multitoque:
  - cada dedo é identificado pelo **índice** e fica preso ao destino onde encostou (botão, direcional ou área da câmera) até ser levantado ou cancelado pelo sistema;
  - arrastar a câmera por cima de um botão não aperta o botão;
  - quando as margens de toque de dois botões se sobrepõem, vale o botão de centro mais próximo.
- **A ação `sprint` tem um único dono** (`TouchControls`): o personagem corre se o botão CORRER estiver ligado ou o direcional estiver na zona de corrida, e só enquanto o direcional estiver em uso. Antes, direcional e botão escreviam na mesma ação e podiam se anular.
- **`TouchActionButton`** ganhou modos:
  - `HOLD`: atacar, pular, defender, usar;
  - `TOGGLE`: correr;
  - `TAP`: alternar câmera.

### Organização da tela

| Região | Controle |
|---|---|
| Lado esquerdo (42% da largura) | Direcional flutuante |
| Centro e direita, fora dos botões | Rotação da câmera |
| Canto inferior direito | ATACAR (maior), PULAR, AGACHAR, CORRER, USAR, DEFESA, cada um com área exclusiva |
| Canto superior direito | 1ª P / 3ª P |

## 2. Personagem

### Antes

Corpo "Superhero", com dorsais e deltoides de fisiculturista, e roupas geradas como cascas da própria malha:
- o tecido mostrava os músculos;
- **os dedos dos pés apareciam através das botas**;
- as barras ficavam serrilhadas.

### Agora

- **Roupa modelada de verdade**, do pacote Quaternius *Modular Character Outfits – Fantasy* (versão gratuita, CC0):
  - camisa com gola, alamares e cinto (tingida de oliva);
  - mangas dobradas;
  - mãos e antebraços com pele;
  - calça com dobras;
  - botas de couro de cano alto com fivelas.
- **Esqueleto em proporções naturais ("Regular")**, que vem no mesmo pacote. Tem a mesma hierarquia e as mesmas alturas do anterior; ombros e quadris são cerca de 2 cm mais estreitos.
  - Todas as animações continuam compatíveis e foram retargetadas de novo para ele. A passada de corrida medida mudou de 1,38 para 1,28 m, e a física acompanha esse valor.
- **Cabeça, barba, cabelo e olhos** vêm do corpo-base anterior. As peles (`Skin`) ligam pelo nome do osso, então a cabeça segue o osso `Head` do novo esqueleto sem edição de vértices.
- **Texturas:** de 4K para 2K/1K, com compressão de vídeo e mipmaps.
- **Primeira pessoa:** a roupa e as mãos ficam visíveis; a cabeça vira só sombra.

Ferramenta: `tools/build_survivor.gd`.

## 3. Animação

O sistema continua sendo o `BodyAnimator`, um compositor por camadas guiado pela física.

**Por que não `AnimationTree`:** o `BlendSpace` sincroniza animações pelo tempo; aqui a locomoção é tocada pela **fase da passada física** (distância percorrida), alinhada ao contato do calcanhar medido em cada captura. É isso que impede o pé de deslizar. A máquina de estados explícita foi usada onde ela é a ferramenta certa: no combate (seção 5).

Novidades:
- **Pés plantados ao girar parado:** girando a visão sem andar, as pernas ficam no lugar e a pélvis compensa.
  - Acima de 50° de torção, ou com mais de 15° por 0,7 s, o personagem dá um **passo de ajuste** com meio ciclo da caminhada capturada, só nas pernas.
- **Inclinação pela aceleração real da cápsula:**
  - o tronco inclina para a frente na arrancada, para trás na frenagem e para dentro nas curvas;
  - o ângulo é 60% do ângulo de equilíbrio `atan(a/g)`, com limite de 12°.
- **Parada gradual:** a locomoção acompanha a desaceleração física, sem corte.
- **Defesa:**
  - guarda com os dois punhos diante do rosto, a partir do quadro final de `Melee_Hook_Rec` (captura);
  - impacto na guarda com `Sword_Block`, só do peito para cima;
  - em primeira pessoa, uma **IK de dois ossos** leva os punhos para diante dos olhos, com os cotovelos baixos.
- **Salto:** a pose aérea entra no instante da decolagem (contato real com o chão) e fica até aterrissar.

## 4. Física

- **Mudança de direção como curva:** até 100°, a velocidade **curva** com força centrípeta limitada (`ground_turn_friction`) e o módulo acelera ou freia separadamente.
  - Antes, a parte lateral era freada e a frontal reacelerada, competindo pela mesma aderência. Correr e girar a câmera derrubava a velocidade de 2,1 para 0,2 m/s.
  - Inversões acima de 100° freiam e reaceleram.
- **Terceira pessoa:**
  - o corpo conduz o movimento: o deslocamento não se afasta mais de 35° da frente do corpo, que gira até 540°/s (324°/s correndo);
  - curvas fechadas custam velocidade;
  - quase parado, uma inversão gira o corpo no lugar antes de andar.
- **`action_speed_multiplier`:** a defesa (55%) e o golpe carregado (60%) deixam o personagem mais lento e impedem a corrida.
- **Mantido das etapas 1 e 2:** aceleração progressiva, frenagem, círculo de atrito por superfície, encostas, quedas com dano, degraus e empurrar objetos.

## 5. Combate (`scripts/player/melee_combat.gd`)

Máquina de estados explícita:

```
IDLE ── ATACAR ──> PRESSED ── solta ──> WINDUP ── janela ativa ──> ACTIVE ──> RECOVERY ──> IDLE
                        └── segura ──> CHARGING ── solta ──┘
IDLE ── DEFESA (segurar) ──> BLOCKING ── solta ──> IDLE
```

- **Só o botão de ataque inicia um golpe**, na borda de descida (apertar).
- **Sem fila de comandos:** apertar durante a preparação, o impacto ou a recuperação é ignorado. O teste com 4 toques rápidos resulta em 1 golpe e 1 acerto.
  - Um novo soco só é aceito depois que o braço recolheu, o que permite a sequência um-dois com mãos alternadas.
- **Impacto por colisão, com o alcance real do braço:** durante a janela ativa (em volta do quadro de maior extensão do braço, medido na captura), uma esfera é varrida a partir do **ombro** do braço que golpeia até o **ponto sob a mira**.
  - O comprimento é a **extensão real do braço naquele quadro**: alvo perto é atingido antes, e alvo longe demais não é atingido.
  - Mirar no ponto sob a mira elimina a paralaxe entre olho e ombro. Sem isso, o soco numa caixa acertava o bloco embaixo dela.
- **Recuperação:**
  - o soco rápido termina na própria animação, mais 0,12 s;
  - o gancho volta à guarda com `Melee_Hook_Rec`, mais 0,25 s.
- **Defesa:** golpes e mordidas vindos da frente (cone de cerca de 107°) perdem 75% do dano ao custo de 10 de fôlego; sem fôlego, a guarda cede. Golpes pelas costas passam inteiros.
- **Relógio do jogo:** o combo usa o relógio do jogo, e não o tempo real (antes falhava com variação de quadros).

## 6. Testes

`tests/animation_tests.gd` tem **217 verificações** e `tests/movement_tests.gd` tem **123**. As duas baterias passam no Godot 4.5.1 e no 4.7.1.

Os toques usam o mesmo caminho do Android (`Input.parse_input_event`), **com a emulação de mouse ligada**, para provar a correção na origem.

| # | Teste pedido | Verificação |
|---|---|---|
| 1 | Girar a câmera para esquerda e direita sem atacar | Arrastos de 320 px giram a câmera em 95°, com 0 ataques |
| 2 | Girar para cima e para baixo sem atacar | A inclinação muda, com 0 ataques. Toques curtos na área da câmera e um arrasto que passa por cima do ATACAR também não atacam |
| 3 | Direcional e câmera ao mesmo tempo | Anda a 2,14 m/s enquanto outro dedo gira a câmera. Um terceiro dedo no ATACAR dá exatamente 1 soco e o direcional continua |
| 4 | Ataque sem mexer a câmera | 1 acerto no boneco; câmera inalterada |
| 5 | Correr e trocar de direção | O corpo gira no máximo 324°/s. A direção do deslocamento muda no máximo 2,3° por quadro. A curva custa velocidade (5,8 → 4,97 m/s). Parado, virar para trás gira no lugar antes de andar |
| 6 | Parar de correr | Sem parada instantânea. Desaceleração contínua até parar em 0,45 s. O tronco inclina para trás ao frear e para a frente ao arrancar |
| 7 | Alternar 1ª e 3ª pessoa | Os 8 cenários da etapa 4 (parado, andando, correndo, agachado, combate, paredes, girando durante a transição, sincronia) |
| 8 | Agachar e levantar | A cabeça desce e volta. Anda agachado na velocidade de agachado |
| 9 | Saltar e aterrissar | Pose aérea desde a decolagem. A queda de 6 m dispara a aterrissagem |
| 10 | Colisões com obstáculos | Correndo contra a parede, a cápsula não entra nela, para e o corpo continua em pé |
| 11 | Sincronização das animações | O pé que pisa está à frente em cada contato físico. A passada da física é igual à da animação. Os pés ficam em fase depois de trocar de câmera |
| 12 | Controles Android | Áreas exclusivas sem sobreposição. CORRER liga a corrida e soltar o direcional a desliga. DEFESA ergue a guarda. Botão de câmera. ATACAR e USAR |

Outros testes da bateria:
- pés plantados: girando 30°, o pé desliza menos de 6 cm, depois vem o passo de ajuste, e a torção nunca passa de 65°;
- defesa: 20 de dano pela frente vira 5, pelas costas passa inteiro, e de guarda o personagem não corre;
- em primeira pessoa, os dois punhos da guarda ficam no campo de visão;
- alcance real: a 0,9 m a mais, o soco não alcança;
- um-dois alterna as mãos;
- golpe carregado;
- caixa empurrada pelo soco;
- ragdoll nas duas câmeras;
- desempenho do animador: cerca de 0,4 ms por quadro.

## 7. Arquivos modificados

| Arquivo | Mudança |
|---|---|
| `tools/setup_input_map.gd`, `project.godot` | botões do mouse só no mouse físico; ação `block` (Q, botão direito, LB) |
| `scripts/autoload/game_input.gd` | ignora mouse emulado |
| `scripts/ui/touch_controls.gd` | roteador por índice de dedo, dono único da corrida, toques cancelados, `get_target_at` |
| `scripts/ui/touch_action_button.gd` | modos HOLD, TOGGLE e TAP; área de acerto com prioridade ao centro mais próximo |
| `scripts/ui/touch_move_stick.gd` | não escreve mais a ação de correr |
| `scenes/ui/touch_controls.tscn` | novo layout com CORRER e DEFESA |
| `scripts/player/melee_combat.gd` | reescrito: máquina de estados, impacto pelo braço, recuperação, defesa |
| `scripts/components/health_component.gd` | `damage_filter` (defesa e, no futuro, armadura) |
| `scripts/player/player_controller.gd` | curva centrípeta, condução pelo corpo em 3ª pessoa, `action_speed_multiplier` |
| `scripts/player/movement_settings.gd` | passada de corrida de 1,28 m (medida no novo esqueleto) |
| `scripts/animation/body_animator.gd` | pés plantados, passo de ajuste, inclinação, guarda, IK da guarda em 1ª pessoa, salto pelo contato real |
| `tools/build_survivor.gd` | reescrito: roupa modelada, esqueleto "Regular", cabeça do corpo-base, texturas reduzidas |
| `tools/retarget_animations.gd` | alvo no novo esqueleto; clipes de recuperação do gancho e impacto na guarda |
| `scenes/characters/survivor.tscn`, `resources/models/survivor/*`, `resources/animations/survivor_body.res` | gerados pelas ferramentas |
| `tests/animation_tests.gd` | 12 testes obrigatórios e os demais da seção 6 |

## 8. Limitações honestas

- **Animações:** as versões gratuitas das bibliotecas Quaternius não têm andar de lado, giro no lugar nem paradas capturadas. Giro e parada são feitos com a física sobre as capturas (pés plantados, passo de ajuste, inclinação), e não com animações dedicadas.
  - A versão paga (UAL Pro) tem essas animações e entraria sem mudança de código, pelo mesmo esqueleto.
- **Roupa medieval rústica:** a versão gratuita do pacote só tem roupas medievais. A camisa de camponês tingida de oliva e as botas de couro passam por roupa de trabalho rústica, mas não por roupa militar moderna. A mesma ferramenta aceita outras roupas do mesmo esqueleto.
- **Defesa contra golpes de zumbis:** ainda não há zumbis. A defesa foi testada com dano direcional aplicado direto, e o contrato (`damage_filter`, direção do golpe) já está pronto para eles.
- **Validação em aparelho:** os testes simulam os toques do Android, mas a sensação ao toque e o desempenho só se confirmam no celular.
