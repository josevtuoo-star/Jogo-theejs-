# Etapa 1 — Personagem em primeira pessoa

## O que foi implementado

| Mecânica | Como funciona |
|---|---|
| Aceleração e inércia | a velocidade se aproxima da desejada com aceleração (11 m/s²) e frenagem (14 m/s²) separadas; em curvas, a componente lateral é freada à parte, então o corpo perde velocidade ao mudar de direção |
| Caminhada / corrida / agachado | 2,6 / 5,4 / 1,25 m/s; para trás 65%, de lado 85%; o analógico parcial gera velocidade proporcional |
| Rampas | inclinação máxima caminhável de 46°; a subida reduz a velocidade proporcionalmente ao seno da inclinação; acima de 46° o corpo não sobe |
| Degraus | sobe obstáculos até 32 cm sem saltar (teste de elevação + avanço + raio de apoio); desce colado aos degraus |
| Salto | altura física exata (0,55 m), coyote time e buffer de 0,12 s, intervalo de 0,35 s entre saltos, custa resistência; exausto, salta mais baixo; saltar agachado faz levantar |
| Queda | velocidade terminal de 55 m/s; o impacto é medido na aterrissagem; dano proporcional à energia (quadrado da velocidade): nenhum até 3 m, letal a partir de ~15 m; aterrissagem forte reduz a velocidade por até 0,9 s e absorve parte do momento horizontal |
| Agachar | alterna (C / botão) ou segura (Ctrl); a cápsula e a câmera mudam de altura a 3,2 m/s; não levanta sob teto baixo e levanta sozinho ao sair dele |
| Resistência | correr consome 11/s, saltar 14; regenera após 1,1 s; ao zerar entra em exaustão até recuperar 30% |
| Corpos rígidos | empurra com força limitada a 650 N (uma caixa de 5 kg desliza, um bloco de 300 kg não se move); o peso do jogador (80 kg) é aplicado sobre o que ele pisa |
| Câmera | balanço sincronizado com a passada real (um passo a cada 0,72–1,15 m), inclinação de 1,2° ao andar de lado, mola amortecida na aterrissagem, suavização ao subir degraus, +4° de FOV ao correr |
| Toque | direcional flutuante analógico (lado esquerdo), empurrar para frente além da borda = correr, arrasto no lado direito = olhar, botões PULAR e AGACHAR; multitoque com cada dedo preso ao seu controle |
| PC e gamepad | WASD/setas, Shift, Espaço, C, Ctrl, mouse capturado (Esc libera); analógicos e botões do gamepad |
| Diagnóstico | HUD com FPS, estado, velocidade, resistência, impacto e passos (F3) |

## Onde fica cada arquivo

| Arquivo | Função |
|---|---|
| `project.godot` | Jolt Physics, renderizador Mobile, orientação paisagem, InputMap, nomes das camadas, autoload `GameInput` |
| `scripts/autoload/game_input.gd` | autoload **GameInput**: acumula a rotação de visão de mouse, toque e gamepad; captura do mouse |
| `scripts/player/movement_settings.gd` | `Resource` com todos os parâmetros físicos (classe `MovementSettings`) |
| `resources/player/default_movement_settings.tres` | valores padrão, editáveis no Inspector |
| `scripts/player/player_controller.gd` | `PlayerController` (raiz `CharacterBody3D` do jogador) |
| `scripts/player/camera_effects.gd` | `PlayerCameraEffects` (nó entre a cabeça e a câmera) |
| `scripts/components/stamina_component.gd` | `StaminaComponent` (filho do jogador) |
| `scenes/player/player.tscn` | cena do jogador |
| `scripts/ui/touch_move_stick.gd` | direcional de toque (`TouchMoveStick`) |
| `scripts/ui/touch_action_button.gd` | botão de ação de toque (`TouchActionButton`) |
| `scripts/ui/touch_controls.gd` | roteador multitoque (`TouchControls`) |
| `scenes/ui/touch_controls.tscn` | camada de controles de toque |
| `scripts/debug/movement_debug_hud.gd` | HUD de diagnóstico |
| `resources/materials/dev_grid.gdshader` | shader de grade de 1 m usado na cena de calibração |
| `scenes/test/movement_test_gym.tscn` | cena de calibração: escada, blocos de 10–45 cm, rampas de 15–55°, túnel de 1,35 m, torre de queda de 3 e 6 m, paredes, objetos de 5/15/20/300 kg |
| `tests/movement_tests.gd`, `tests/test_runner.tscn` | testes automatizados |
| `tools/setup_input_map.gd` | regrava o InputMap padrão no `project.godot` |
| `tools/build_test_gym.gd` | regenera a cena de calibração |

Árvore da cena do jogador:

```
Player (CharacterBody3D, player_controller.gd)   camada 2, máscara 1+3, origem nos pés
├── CollisionShape3D (CapsuleShape3D r=0,30 h=1,80)
├── Head (Node3D)                  altura dos olhos; recebe a arfagem (olhar cima/baixo)
│   └── CameraEffects (Node3D, camera_effects.gd)
│       └── Camera3D               FOV 75, near 0,05, far 400
└── Stamina (Node, stamina_component.gd)
```

A guinada (olhar para os lados) gira o corpo inteiro; a arfagem gira só a cabeça.

## Como abrir e jogar

1. Abra a pasta do projeto no Godot 4.5 ou superior (testado em 4.5.1 e 4.7.1).
2. F5 abre `scenes/test/movement_test_gym.tscn`.
3. No PC: clique para capturar o mouse; WASD, Shift corre, Espaço salta, C alterna agachar, Ctrl agacha segurando, Esc libera o mouse, F3 mostra/oculta o diagnóstico.
4. Para ver os controles de toque no PC, ative `ultimo_amanhecer/input/force_touch_controls` em Configurações do Projeto e também *Input Devices → Pointing → Emulate Touch From Mouse*.

## Testes automatizados

```
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

Para rodar só um grupo: `... res://tests/test_runner.tscn -- --only=stairs`.

Resultado nesta entrega: **75 de 75 verificações aprovadas no Godot 4.5.1 e no 4.7.1**. Os testes rodam a cena de calibração real e cobrem: aceleração e distância de frenagem, velocidades por direção e analógico parcial, corrida, exaustão e recuperação, altura do salto e intervalo entre saltos, túnel (bloqueado em pé, passa agachado, não levanta nem salta sob o teto, levanta ao sair), escada de 18 cm (subida e descida colada), limite de degrau (sobe 10/20/30 cm, não sobe 45 cm), rampas de 15/30/45° com perda de velocidade e bloqueio em 55°, quedas de 1 a 16 m (impacto medido, dano, letalidade), empurrar 5 kg e não mover 300 kg, ficar de pé sobre um corpo rígido, e controles de toque com eventos multitoque injetados (direcional, zona de corrida, visão, botões).

A cena também foi renderizada (OpenGL por software) para confirmar que o shader compila e que HUD e controles de toque aparecem.

## Exportar para Android

1. Instale os *Export Templates* da mesma versão do Godot (Editor → Manage Export Templates).
2. Instale o JDK 17 e o Android SDK; informe os caminhos em Editor → Editor Settings → Export → Android.
3. Projeto → Exportar → Adicionar → Android. Arquitetura `arm64-v8a`. A compressão ETC2/ASTC já está ativada no projeto.
4. Use o keystore de depuração para testes. Keystores de release nunca entram no repositório (`.gitignore` já bloqueia).

## Ajustes finos

Todos os números ficam em `resources/player/default_movement_settings.tres` (Inspector) e nas propriedades exportadas de `CameraEffects` e `Stamina` na cena do jogador. Para um personagem diferente (ex.: ferido), duplique o `.tres` e atribua ao jogador.

## Limitações conhecidas e decisões

- **Não testado em aparelho físico.** O toque foi verificado com eventos injetados na viewport, e o desempenho no Android ainda precisa ser medido no celular. Esse é o primeiro passo de validação desta etapa no seu aparelho.
- **Ao subir um degrau**, a cápsula é elevada de uma vez (até 32 cm). A câmera compensa e sobe de forma suave.
- **Teletransporte:** no Jolt, mover um corpo cinemático por transformação gera uma velocidade implícita que arremessava objetos no destino. `PlayerController.teleport()` desliga a camada de colisão do jogador durante esse passo de física, e um teste cobre o caso.
- **Plataformas:** só a camada "mundo" transmite velocidade de plataforma ao jogador. Objetos físicos soltos (caixas, barris) não carregam o jogador se ele estiver em cima deles.
- **Interpolação de física** está desligada: física a 60 Hz e visão aplicada por quadro. Em telas de 90/120 Hz, ligar a interpolação será avaliado na etapa de otimização, com medição em aparelho.
- No modo headless, o Jolt imprimiu uma vez o aviso "job system exceeded the maximum number of jobs" durante a bateria de testes. O resultado dos testes não foi afetado; isso será acompanhado na etapa de otimização.
