# Último Amanhecer — Arquitetura

Sobrevivência com zumbis em primeira pessoa (com terceira pessoa opcional, como em DayZ). Godot 4.5+ (testado em 4.5.1 e 4.7.1), GDScript, renderizador **Mobile**, física **Jolt**. Plataforma inicial: Android (paisagem). PC depois.

## Princípios

1. **Física real primeiro.** Movimento, quedas, empurrões e golpes são resolvidos pelo motor de física. Animações e câmera só *refletem* o estado físico e nunca o substituem.
2. **Componentes pequenos e desacoplados.** Cada sistema é um nó com uma responsabilidade (resistência, vida, inventário…). A comunicação acontece por **sinais**: quem emite não conhece quem escuta.
3. **Dados separados do código.** Parâmetros ajustáveis ficam em `Resource` (`.tres`), editáveis no Inspector sem tocar no script.
4. **Uma única fonte de entrada.** Teclado, gamepad e toque pressionam as mesmas ações do `InputMap`; a visão passa pelo autoload `GameInput`. A jogabilidade não sabe de onde veio o comando.
5. **Testes automatizados headless.** Cada etapa entrega testes que rodam a cena real (`tests/`). Uma etapa só termina quando os testes passam.
6. **Desempenho no Android.** Sem alocação por quadro nos caminhos quentes (consultas de física reutilizam objetos), sombras e distâncias limitadas, shaders simples.

## Estrutura de pastas

```
project.godot              Configuração (Jolt, Mobile, InputMap, camadas)
docs/                      Arquitetura e documentação de cada etapa
scenes/
  player/player.tscn       Personagem jogável (cápsula física + corpo + câmera)
  characters/survivor.tscn Corpo do sobrevivente (gerado por tools/build_survivor.gd)
  demo/demo_forest.tscn    Cena principal: clareira na floresta (tools/build_demo_map.gd)
  ui/touch_controls.tscn   Controles de toque
  test/                    Cenas de calibração (não são o mapa do jogo)
scripts/
  autoload/                Singletons (GameInput)
  components/              Componentes reutilizáveis (StaminaComponent; depois Health, Hunger, Thirst…)
  player/                  Controlador, interação, combate, morte (ragdoll)
  camera/                  Câmera em 1ª/3ª pessoa com transição (PlayerCameraRig)
  animation/               Animador do corpo inteiro (BodyAnimator)
  interaction/             Interactable e objetos interagíveis
  world/                   Perigos, alvos, fogueira, instâncias de vegetação (ScatterInstances)
  physics/                 SurfaceProfile e utilidades físicas
  ui/                      Controles de toque e HUD
  debug/                   Ferramentas de diagnóstico
resources/
  player/                  Parâmetros (.tres)
  surfaces/                Perfis de superfície (.tres)
  materials/               Shaders (terreno, árvores) e materiais
  animations/              Biblioteca retargetada do corpo (survivor_body.res)
  models/                  Malhas geradas (roupas, terreno)
  textures/trees/          Atlas de impostores das árvores
tests/                     Testes automatizados (cena + script)
tools/                     Ferramentas de produção (InputMap, retarget, personagem, impostores, mapa)
assets/                    Assets de terceiros (CC0), cada pasta com licença/SOURCE.txt
  _source/                 Pacotes originais grandes (fora do Git e do APK)
```

## Camadas de física

| Camada | Nome | Quem usa | Máscara típica |
|---|---|---|---|
| 1 | mundo | cenário estático, terreno, construções | — |
| 2 | jogador | `CharacterBody3D` do jogador | 1, 3 |
| 3 | objetos_fisicos | `RigidBody3D` soltos (caixas, latas, cadáveres em ragdoll) | 1, 2, 3 |
| 4 | zumbis | corpo de movimento dos zumbis | 1, 2, 3, 4 |
| 5 | interagiveis | áreas de interação (itens, portas) | — |
| 6 | hitboxes | partes do corpo atingíveis (cabeça, tronco, membros) | — |
| 8 | ragdoll | ossos físicos do corpo morto | 1, 3 |

## Contrato de sinais do jogador

`PlayerController` emite (os sistemas futuros só se conectam):

| Sinal | Uso previsto |
|---|---|
| `footstep(intensity, is_left_foot, surface)` | áudio de passos por superfície, ruído que atrai zumbis, animação |
| `landed(impact_speed)` | som e câmera de aterrissagem |
| `fall_damage_taken(amount, impact_speed)` | `HealthComponent` (etapa 4) |
| `jumped(vertical_speed)` | som, animação, ruído |
| `stance_changed(stance)` | animação, furtividade (agachado faz menos ruído) |
| `movement_state_changed(state)` | `AnimationTree` dos braços/corpo |
| `stepped_up(height)` | suavização da câmera |
| `wall_impact(speed, normal)`, `head_bumped(speed)` | câmera, som, dano (etapa 5) |
| `surface_changed(surface)`, `slide_started`, `slide_ended` | áudio, partículas, animação |

`HealthComponent` emite `damaged(amount, kind, direction)`, `died` e `revived`. `BodyAnimator` emite `animation_event(event, animation)` (`hit`, `contact`): combate e interação agem nesse quadro. `PlayerCameraRig` emite `mode_changed(third_person)` e `transition_finished(third_person)`. Alvos de golpes implementam `receive_hit(hit: Dictionary)`, com as chaves `damage`, `impulse`, `direction`, `point`, `kind` e `attacker`.

Propriedades de entrada para outros sistemas: `carried_mass` (kg carregados, definido pelo inventário), `external_speed_multiplier` (ferimentos, pernas quebradas), `input_enabled`, `look_enabled` (menus e inventário). `StaminaComponent.regen_multiplier` recebe fome e sede.

## Etapas

Cada etapa só começa depois que a anterior passa nos testes e é validada no aparelho.

| # | Etapa | Conteúdo | Situação |
|---|---|---|---|
| 1 | **Personagem e movimento** | controlador físico, câmera, agachar, salto, queda, degraus, rampas, empurrar objetos, resistência, controles de toque | **concluída** (`ETAPA_01_PERSONAGEM.md`) |
| 2 | **Física avançada de movimentação** | perfis de velocidade, aderência por superfície, inércia, carga, arrasto do ar, encostas, impactos | **concluída** (`ETAPA_02_FISICA_AVANCADA.md`) |
| 3 | **Animações em primeira pessoa** | rig e 19 animações autorais, animador em camadas sincronizado com a passada, vida e lesões, interação, combate corpo a corpo, morte e renascer, HUD | **concluída** (`ETAPA_03_ANIMACOES.md`) |
| 4 | **Reconstrução visual e câmera** | corpo humano completo (CC0) com roupas, animações retargetadas, primeira pessoa verdadeira, câmera 1ª/3ª pessoa, ragdoll, cenário PBR, HUD | **concluída** (`ETAPA_04_RECONSTRUCAO.md`) |
| 5 | **Correção profunda da jogabilidade** | origem do soco ao arrastar no toque, controles por índice de dedo e áreas exclusivas, personagem em proporções naturais com roupa modelada, pés plantados, inclinação pela aceleração, curvas centrípetas, combate em máquina de estados com impacto pelo braço, defesa | **concluída** (`ETAPA_05_JOGABILIDADE.md`) |
| 6 | Interação e inventário | itens como `RigidBody3D` reais, pegar e soltar (animação `pickup` já existe), inventário por peso e volume (define `carried_mass`), portas, UI de toque | próxima |
| 7 | Status vitais | fome, sede, sangramento, cura; a vida e as lesões já existem | — |
| 8 | Armas | armas brancas e de fogo (recuo, dispersão, munição) sobre o combate da etapa 3 | — |
| 9 | Zumbis | mesmo esqueleto do sobrevivente (Quaternius UAL 1/2, CC0), `NavigationAgent3D`, percepção por visão e ruído (passos com superfície), ataques com `receive_hit` | — |
| 10 | Ragdoll parcial e reações | o ragdoll de morte já existe (etapa 4); falta mistura física parcial em golpes fortes e zumbis | — |
| 11 | Otimização Android | perfis de qualidade, LOD, testes em aparelhos reais | — |
| 12 | PC | configurações gráficas e de controle | — |

O mundo aberto não faz parte destas etapas.

## Assets

O registro completo, com o que está em uso, o que foi aprovado e o que foi rejeitado, fica em [`ASSET_LICENSES.md`](../ASSET_LICENSES.md). Ao adicionar assets:

- cada recurso entra em `assets/<categoria>/<nome>/` com o arquivo de licença original e uma linha em `ASSET_LICENSES.md` (origem, autor, licença, restrições);
- a licença é verificada **por arquivo**, no momento do download, na página do autor; não se presume que a licença do repositório cobre os modelos e o áudio;
- recursos restritos a uso não comercial ou só a testes ficam fora do repositório público e fora de builds distribuídas.

Fontes a avaliar, com o que precisa ser conferido em cada uma:

| Fonte | O que conferir antes de usar |
|---|---|
| Poly Haven, ambientCG | texturas, HDRIs e modelos publicados como CC0; conferir a página de cada item |
| Kenney, Quaternius | pacotes publicados como CC0; conferir o arquivo de licença dentro de cada pacote |
| Mixamo (Adobe) | exige conta Adobe e download feito por você; conferir os termos atuais de uso em jogos e a proibição de redistribuir os arquivos brutos |
| Sketchfab | a licença é definida por modelo (CC0, CC BY, CC BY-NC, licenças pagas da loja); usar apenas as que permitem o uso pretendido e cumprir a atribuição |
| GitHub | a licença do código raramente cobre os modelos; exigir licença explícita para os assets |
