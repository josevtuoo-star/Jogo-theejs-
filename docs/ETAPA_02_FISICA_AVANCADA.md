# Etapa 2 — Física avançada de movimentação

Objetivo: dar peso real ao movimento, inspirado na sensação de DayZ: arrancar e frear leva alguns passos, correr exige espaço para fazer curvas, o terreno e a carga importam. Ao mesmo tempo, o personagem não pode parecer que patina.

## Modelo físico

### 1. Velocidade desejada

| Perfil | Como ativar | Velocidade |
|---|---|---|
| Andar | direcional até 60% inclinado, ou modo andar (Alt / R3) | até 1,5 m/s |
| Trotar (padrão) | direcional todo inclinado / WASD | 3,6 m/s, sem gastar resistência |
| Correr | Shift / L3 / empurrar o direcional de toque além da borda | 5,8 m/s, gasta resistência |
| Agachado | C (alterna) / Ctrl (segura) | até 1,25 m/s |

Entre 60% e 100% de inclinação do direcional, a velocidade sobe continuamente do andar ao trote. Essa velocidade é multiplicada por:

- direção: 85% de lado, 65% para trás;
- superfície (`SurfaceProfile.speed_multiplier`): lama 75%;
- carga: sem efeito até 15 kg, cai até 60% com 50 kg;
- recuperação de impacto (aterrissagem forte, colisão em corrida);
- inclinação do terreno:
  - subida: `1 − 0,55·senθ`;
  - descida: `1 + 0,35·senθ − 0,9·sen²θ`, ou seja, um pouco mais rápido em rampa suave e contido em rampa íngreme;
  - atravessar a encosta na horizontal não muda a velocidade.

### 2. Aceleração, frenagem e curvas

- **Aceleração dependente da velocidade:** 9 m/s² ao arrancar, caindo para 45% disso perto da velocidade de corrida, como no corpo humano. O trote chega em ~0,47 s e a corrida a 95% em ~0,87 s.
- **Frenagem:** 12 m/s². Do trote, para em ~0,5 m (meio passo); da corrida, em ~1,35 m.
- **Atrito lateral em curvas:** a componente da velocidade fora da direção desejada é freada separadamente. Uma curva de 90° correndo leva ~0,47 s e o momento carrega o corpo ~1,4 m na direção antiga; trotando, 0,30 s e ~0,5 m.

### 3. Aderência (círculo de atrito)

Toda variação de velocidade horizontal no chão, em qualquer direção, fica limitada a `μ · g · 1,3` por segundo, onde μ é o atrito da superfície. Em terra e asfalto (μ = 1,0) o limite é 12,8 m/s², então o personagem responde normalmente. No gelo (μ = 0,08) o limite é 1,0 m/s²: ele leva segundos para ganhar velocidade e desliza metros até parar.

### 4. Sem micro-deslizes

- **Pé plantado:** sem comando e abaixo de 0,3 m/s, o corpo para por completo (em superfícies escorregadias esse limiar cai com μ²).
- **Parado em rampa até 46°:** deriva zero.
- **Passada ligada à distância real:** a câmera balança e os passos acontecem a cada 0,65 m (andando) até 1,2 m (correndo). Enquanto o corpo freia, ele continua dando passos, em vez de patinar.

### 5. Massa e carga

`carried_mass` (kg) é a carga que o inventário vai definir na Etapa 3. Ela reduz:

- aceleração e frenagem, na razão `m_corpo / m_total` (mesma força das pernas sobre mais massa);
- velocidade máxima, como descrito acima;
- altura do salto: `h · (m_corpo / m_total)^1,5` (com 40 kg de carga, 0,55 m → 0,30 m);
- força de empurrar, também limitada por `μ · m_total · g` (no gelo não se empurra nada pesado).

A carga também multiplica o custo de resistência.

### 6. Ar e quedas

- **Gravidade com arrasto aerodinâmico quadrático:** `a = −g + k·v²`, com `k = g / vt²` e velocidade terminal de 55 m/s. Uma queda de 6 s chega a 43,4 m/s (seriam 59 m/s sem arrasto).
- **No ar:** o momento é preservado e o controle é pequeno (1,6 m/s²).
- **Impacto da aterrissagem:** é a componente da velocidade normal ao piso. Cair numa rampa dói menos que cair no plano.
- **Dano de queda:** quadrático (energia). Nenhum até 3 m, letal a partir de ~15 m.
- **Aterrissagem forte:** reduz a mobilidade por até 0,9 s e absorve parte do momento horizontal.

### 7. Terreno inclinado

- **Até 46°:** caminhável, com as velocidades da seção 1.
- **De 46° a 80°:** o corpo escorrega com atrito cinético. A aceleração ao longo da encosta é `g·(senθ − μ·0,5·cosθ)` e o limite é 10 m/s. Ao escorregar, o jogador só consegue se desviar para os lados; empurrar morro acima é descartado. O estado é `SLIDING`.
- **Correr em subida:** gasta `1 + 1,5·senθ` vezes mais resistência (1,75× a 30°).

### 8. Degraus

- **Subida:** degraus de até 32 cm, sem saltar.
- **Descida ativa:** ao perder o piso andando (sem saltar), o corpo procura piso caminhável até 32 cm abaixo e assenta nele. Isso mantém o personagem colado a escadas mesmo trotando e correndo. Uma borda mais alta que isso vira queda de verdade.

### 9. Colisões

| Evento | Quando | Efeito |
|---|---|---|
| `wall_impact(velocidade, normal)` | a partir de 2,5 m/s contra parede | acima de 4,2 m/s (corrida), o personagem cambaleia |
| `head_bumped(velocidade)` | cabeça bate no teto ao saltar | o salto é cortado na hora |
| `landed(impacto)` / `fall_damage_taken` | aterrissagem | conforme a seção 6 |

Os três eventos movem a câmera com molas amortecidas.

### 10. Câmera

- **Inércia da cabeça:** o tronco inclina para frente ao acelerar (~0,7°) e para trás ao frear (~1°), e lateralmente nas curvas.
- **Inclinação lateral:** ao andar de lado e ao escorregar.
- **Balanço e FOV:** o balanço continua sincronizado com a passada e o FOV de corrida foi mantido.

## Arquivos

| Arquivo | O que mudou |
|---|---|
| `scripts/player/player_controller.gd` | modelo completo descrito acima |
| `scripts/player/movement_settings.gd` | novos parâmetros: perfis de velocidade, aderência, descida, deslizamento, carga, colisões |
| `scripts/physics/surface_profile.gd` | **novo**: `SurfaceProfile` (μ, velocidade, resistência, id para áudio) |
| `resources/surfaces/terra.tres`, `grama.tres`, `lama.tres`, `gelo.tres` | **novos**: perfis de superfície |
| `scripts/player/camera_effects.gd` | inércia da cabeça, impactos em parede e teto, inclinação ao escorregar |
| `scripts/debug/movement_debug_hud.gd` | velocidade-alvo, superfície e μ, carga, impacto em parede; F4 alterna a carga de teste |
| `scenes/player/player.tscn` | superfície padrão = terra |
| `scenes/test/movement_test_gym.tscn` | placas de gelo e lama, viga a 2,15 m (gerada por `tools/build_test_gym.gd`) |
| `project.godot` | ações `walk_toggle` (Alt / R3) e `debug_cycle_load` (F4) |
| `tests/movement_tests.gd` | 123 verificações (antes 75) |

### Como aplicar uma superfície no cenário

Selecione o `StaticBody3D` do piso → Inspector → Metadata → adicione `surface_profile` do tipo `Resource` e arraste um `.tres` de `resources/surfaces/`. Sem esse metadado, o atrito do `PhysicsMaterial` do corpo vira o μ. Sem material, vale a superfície padrão do jogador.

### Sinais novos ou alterados

- `footstep(intensidade, pé_esquerdo, superfície)`: agora informa a superfície, para o áudio escolher o som.
- `wall_impact(velocidade, normal)`, `head_bumped(velocidade)`, `surface_changed(superfície)`, `slide_started`, `slide_ended`.
- Estados novos: `JOGGING` e `SLIDING`.
- `is_recovering_from_landing()` foi renomeado para `is_recovering_from_impact()`, porque agora vale também para colisões.

## Como testar

### Testes automatizados

```
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

Para rodar só um grupo: `... -- --only=slope` (ou `ice`, `mud`, `load`, `turn`, `wall`, `stairs`…).

Resultado: **123 de 123 verificações aprovadas no Godot 4.5.1 e no 4.7.1**. Cada teste compara o comportamento medido com a fórmula física correspondente:

| Grupo | O que é verificado |
|---|---|
| Trote | arranque em 0,1 s, 3,60 m/s, parada em 0,51 m / 17 quadros, deriva zero parado |
| Perfis | analógico parcial → caminhada proporcional; 81% → interpolação andar/trote; modo andar = 1,5 m/s |
| Corrida | aceleração decrescente (trote em 0,47 s, corrida em 0,87 s), parada em 1,35 m, inclinação da câmera ao arrancar (−0,7°) e frear (+1,0°) |
| Curva de 90° | correndo 0,47 s e 1,37 m na direção antiga; trotando 0,30 s e 0,53 m |
| Rampas | subida 15/30/45° e descida 15/45° conforme as fórmulas; 55° bloqueia; parado em 30° e 45° deriva 0 |
| Encosta de 55° | escorrega até a base mesmo empurrando para cima; velocidade compatível com o modelo com atrito |
| Resistência | corrida no plano 11/s; subida de 30° 1,75×; lama 1,35× |
| Gelo | 1 s após arrancar: 1,02 m/s (= limite μ·g·1,3); distância de parada = v²/(2a) |
| Carga de 40 kg | trote 2,57 m/s; arranque na razão 0,67; salto 0,30 m |
| Arrasto | após 6 s de queda: 43,4 m/s (modelo `vt·tanh(g·t/vt)` = 43,5) |
| Quedas | 1, 3, 6, 12 e 18 m: impacto com arrasto, dano e letalidade; borda de 1,44 m vira queda |
| Colisões | trotar contra a parede registra impacto sem cambalear; correr registra 5,8 m/s e cambaleia; a viga corta o salto |
| Mantidos da Etapa 1 | escada, limite de degrau, túnel/agachar, salto, empurrar objetos, toque |

### Teste manual no PC

Abra o projeto e aperte F5. O HUD (F3) mostra estado, velocidade e velocidade-alvo, superfície e μ, carga, resistência e impactos.

1. **Inércia:** corra (Shift + W) e solte. O corpo para em pouco mais de um passo, sem patinar. Trotando, para quase na hora.
2. **Curvas:** corra em linha reta e gire o mouse 90°. O corpo faz um arco; trotando, a curva é bem mais fechada.
3. **Andar:** aperte Alt para o modo andar (1,5 m/s); aperte de novo para voltar ao trote.
4. **Rampas** (à direita do spawn): suba e desça as de 15°, 30° e 45° e compare a velocidade no HUD. Pare no meio de uma: o personagem não escorrega. Tente subir a vermelha (55°): impossível. Pule de cima da plataforma da torre (6 m) sobre uma rampa e veja o impacto menor.
5. **Encosta íngreme:** suba uns 2 m da rampa de 45°, vire para a direita e salte sobre a rampa vermelha de 55°, que fica ao lado. O personagem escorrega até a base, e empurrar para cima não adianta.
6. **Gelo** (placa azul, à esquerda ao fundo): arranque, freie e faça curvas. Tudo desliza.
7. **Lama** (placa marrom, atrás à direita): passada mais lenta e corrida mais cansativa.
8. **Carga:** F4 alterna 0/20/40/60 kg. Compare arranque, velocidade e altura do salto.
9. **Paredes e viga:** corra contra a parede do fundo (tranco e cambaleio) e salte embaixo da viga perto do spawn (a cabeça bate).
10. **Escada:** suba e desça trotando e correndo. Os pés ficam colados aos degraus.

### Teste no Android

Exporte como descrito em `ETAPA_01_PERSONAGEM.md`. No celular:

- direcional pouco inclinado = andar; todo inclinado = trotar; além da borda, para frente = correr;
- a sensação de peso deve ser a mesma do PC;
- se o arranque parecer lento no toque, o primeiro ajuste é `ground_acceleration` em `resources/player/default_movement_settings.tres`.

## Ajuste fino

Todos os números estão no Inspector:

- `resources/player/default_movement_settings.tres`: corpo;
- `resources/surfaces/*.tres`: superfícies;
- propriedades de `Head/CameraEffects` em `player.tscn`: câmera.

| Quero… | Ajuste |
|---|---|
| mais peso na corrida | `acceleration_falloff` menor, `ground_turn_friction` menor |
| parar mais rápido | `ground_deceleration` maior (limitado por `traction_grip`) |
| curvas mais abertas correndo | `ground_turn_friction` menor |
| menos balanço de tronco | `lean_pitch_per_acceleration` / `lean_roll_per_acceleration` menores |
| escorregar mais em encostas | `slide_friction_factor` menor |

## Limitações conhecidas

- **Não testado em aparelho físico.** Antes da próxima etapa, é preciso validar no celular a sensação do arranque e da frenagem no toque.
- **Escorregar** usa a mesma cápsula do andar. Rolar ou cair de lado em encostas fica para a etapa de ragdoll (7).
- **Impacto em parede** gera evento e cambaleio, mas ainda não dano: o `HealthComponent` chega na Etapa 4 e só precisa se conectar ao sinal.
- **Objetos físicos** em que o jogador pisa continuam sem transmitir velocidade de plataforma (decisão da Etapa 1).
