class_name MovementSettings
extends Resource
## Parâmetros físicos do personagem em primeira pessoa.
##
## Todos os valores usam unidades do SI (metros, segundos, quilogramas,
## newtons). Os padrões partem de dados de locomoção humana e foram ajustados
## para um movimento pesado, mas responsivo, em touchscreen e no PC.

@export_group("Velocidades (m/s)")
## Caminhada (modo andar, ou direcional pouco inclinado).
@export_range(0.5, 4.0, 0.05) var walk_speed: float = 1.5
## Trote: velocidade padrão com o direcional todo inclinado. Não gasta resistência.
@export_range(1.0, 7.0, 0.05) var jog_speed: float = 3.6
## Corrida. Consome resistência.
@export_range(2.0, 10.0, 0.05) var sprint_speed: float = 5.8
## Deslocamento agachado com o direcional todo inclinado.
@export_range(0.3, 4.0, 0.05) var crouch_speed: float = 1.25
## Fração da inclinação do direcional que corresponde à caminhada. Acima dela,
## a velocidade sobe continuamente da caminhada até o trote.
@export_range(0.1, 0.95, 0.01) var analog_walk_threshold: float = 0.6
## Multiplicador aplicado ao andar de lado.
@export_range(0.1, 1.0, 0.01) var strafe_multiplier: float = 0.85
## Multiplicador aplicado ao andar para trás.
@export_range(0.1, 1.0, 0.01) var backward_multiplier: float = 0.65

@export_group("Aceleração, frenagem e aderência")
## Aceleração a partir do repouso (m/s²).
@export_range(1.0, 40.0, 0.1) var ground_acceleration: float = 9.0
## Fração da aceleração que resta ao atingir a velocidade de corrida. Como no
## corpo humano, arrancar é rápido e chegar à velocidade máxima é gradual.
@export_range(0.05, 1.0, 0.01) var acceleration_falloff: float = 0.45
## Frenagem ao soltar o direcional ou reduzir a velocidade (m/s²).
@export_range(1.0, 40.0, 0.1) var ground_deceleration: float = 12.0
## Atrito lateral em curvas (m/s²). Limita o raio de curva em alta velocidade.
@export_range(1.0, 40.0, 0.1) var ground_turn_friction: float = 14.0
## Aproveitamento do atrito pelas pernas. A variação total de velocidade no
## chão é limitada a μ · g · este fator (círculo de atrito).
@export_range(0.5, 2.0, 0.01) var traction_grip: float = 1.3
## Abaixo desta velocidade, sem comando, o pé planta e o corpo para por
## completo. Em superfícies escorregadias o limiar cai com o quadrado do μ.
@export_range(0.0, 1.0, 0.01) var stop_snap_speed: float = 0.3

@export_group("Terreno inclinado")
## Inclinação máxima caminhável (graus). Acima dela o personagem escorrega.
@export_range(0.0, 89.0, 0.5) var max_floor_angle_degrees: float = 46.0
## Perda de velocidade em subida, proporcional ao seno da inclinação.
@export_range(0.0, 1.0, 0.01) var uphill_penalty: float = 0.55
## Ganho de velocidade em descidas suaves (proporcional ao seno).
@export_range(0.0, 1.0, 0.01) var downhill_bonus: float = 0.35
## Contenção em descidas íngremes (proporcional ao quadrado do seno).
@export_range(0.0, 2.0, 0.01) var downhill_penalty: float = 0.9
## Custo extra de resistência ao correr em subida (proporcional ao seno).
@export_range(0.0, 5.0, 0.05) var uphill_stamina_factor: float = 1.5
## Fração do μ da superfície usada como atrito cinético ao escorregar.
@export_range(0.0, 1.5, 0.01) var slide_friction_factor: float = 0.5
## Inclinação máxima considerada encosta (acima disso é parede).
@export_range(50.0, 89.0, 0.5) var max_slide_angle_degrees: float = 80.0
## Velocidade máxima ao escorregar (m/s).
@export_range(1.0, 30.0, 0.1) var max_slide_speed: float = 10.0
## Aceleração lateral que o jogador consegue exercer escorregando (m/s²).
@export_range(0.0, 10.0, 0.1) var slide_control_acceleration: float = 2.0
## Distância de "grudar" no chão ao descer degraus e rampas.
@export_range(0.0, 1.0, 0.01) var floor_snap_length: float = 0.35
## Altura máxima de degrau que o personagem sobe sem saltar.
@export_range(0.0, 0.6, 0.01) var max_step_height: float = 0.32

@export_group("Ar")
## Controle no ar. Pequeno, para preservar o momento do salto.
@export_range(0.0, 20.0, 0.1) var air_acceleration: float = 1.6
## Velocidade terminal de queda livre de um corpo humano. Define o arrasto
## aerodinâmico quadrático: k = g / vt².
@export_range(10.0, 90.0, 0.5) var terminal_velocity: float = 55.0

@export_group("Salto e queda")
## Altura máxima do centro de massa no salto em pé, sem carga (metros).
@export_range(0.1, 2.0, 0.01) var jump_height: float = 0.55
## Fração da altura do salto quando a resistência está insuficiente.
@export_range(0.0, 1.0, 0.01) var exhausted_jump_factor: float = 0.5
## Tempo após sair de uma borda em que o salto ainda é aceito.
@export_range(0.0, 0.5, 0.01) var coyote_time: float = 0.12
## Tempo em que um toque de salto é lembrado antes de tocar o chão.
@export_range(0.0, 0.5, 0.01) var jump_buffer_time: float = 0.12
## Intervalo mínimo entre aterrissar e saltar de novo (impede "bunny hop").
@export_range(0.0, 2.0, 0.01) var jump_cooldown: float = 0.35
## Impacto (componente normal ao piso) até o qual não há dano (≈ queda de 3 m).
@export_range(1.0, 30.0, 0.1) var safe_impact_speed: float = 7.7
## Impacto que causa dano letal (≈ queda de 15 m).
@export_range(2.0, 60.0, 0.1) var lethal_impact_speed: float = 17.1
## Dano causado por um impacto letal (escala do sistema de vida).
@export_range(1.0, 1000.0, 1.0) var lethal_fall_damage: float = 100.0
## Impacto a partir do qual a aterrissagem reduz temporariamente a velocidade.
@export_range(1.0, 30.0, 0.1) var stagger_impact_speed: float = 4.5
## Duração máxima da redução de velocidade após um impacto forte.
@export_range(0.0, 3.0, 0.01) var stagger_max_duration: float = 0.9
## Multiplicador de velocidade mínimo durante a recuperação.
@export_range(0.0, 1.0, 0.01) var stagger_min_speed_multiplier: float = 0.35

@export_group("Colisões")
## Velocidade contra uma parede a partir da qual o impacto é registrado.
@export_range(0.5, 10.0, 0.1) var wall_impact_min_speed: float = 2.5
## Velocidade contra uma parede a partir da qual o personagem cambaleia.
@export_range(0.5, 15.0, 0.1) var wall_stagger_speed: float = 4.2
## Velocidade vertical mínima para registrar batida de cabeça no teto.
@export_range(0.1, 10.0, 0.1) var head_bump_min_speed: float = 0.8

@export_group("Corpo e carga")
## Massa do sobrevivente com roupas (kg).
@export_range(30.0, 200.0, 0.5) var body_mass: float = 80.0
## Força horizontal máxima que o personagem consegue aplicar empurrando (N).
@export_range(0.0, 3000.0, 10.0) var max_push_force: float = 650.0
## Carga (kg) que não afeta a velocidade máxima.
@export_range(0.0, 100.0, 0.5) var load_free_mass: float = 15.0
## Carga (kg) em que a penalidade de velocidade é máxima.
@export_range(1.0, 200.0, 0.5) var load_max_mass: float = 50.0
## Multiplicador de velocidade com a carga máxima.
@export_range(0.1, 1.0, 0.01) var load_max_speed_multiplier: float = 0.6
## Expoente da redução do salto com a massa total: altura · (m_corpo/m_total)^n.
## Com força das pernas constante seria 2; 1,5 considera o esforço extra sob carga.
@export_range(0.0, 3.0, 0.05) var load_jump_exponent: float = 1.5
@export_range(0.15, 0.6, 0.01) var capsule_radius: float = 0.3
@export_range(1.0, 2.4, 0.01) var standing_height: float = 1.8
@export_range(0.6, 1.6, 0.01) var crouch_height: float = 1.15
## Distância entre o topo da cabeça e a linha dos olhos.
@export_range(0.0, 0.3, 0.01) var eye_offset_from_top: float = 0.12
## Velocidade (m/s) com que a altura do corpo muda ao agachar/levantar.
@export_range(0.5, 10.0, 0.05) var crouch_transition_speed: float = 3.2

@export_group("Passada")
## Comprimento de um passo (m) andando, trotando e correndo. Controla o ritmo
## dos passos, do balanço de câmera e das animações de locomoção. Os valores
## padrão são os medidos nas próprias animações (tools/retarget_animations.gd):
## com a mesma passada, a cadência da física e a da animação coincidem e o pé
## apoiado não desliza no chão.
@export_range(0.2, 2.0, 0.01) var walk_stride: float = 0.63
@export_range(0.2, 3.0, 0.01) var jog_stride: float = 1.39
@export_range(0.2, 3.0, 0.01) var sprint_stride: float = 1.35
@export_range(0.2, 2.0, 0.01) var crouch_stride: float = 0.62

@export_group("Resistência")
## Consumo de resistência por segundo correndo em terreno plano, sem carga.
@export_range(0.0, 100.0, 0.5) var sprint_stamina_drain: float = 11.0
## Custo de resistência de um salto.
@export_range(0.0, 100.0, 0.5) var jump_stamina_cost: float = 14.0

@export_group("Visão")
## Limite do olhar para cima/baixo (graus).
@export_range(45.0, 89.9, 0.1) var max_pitch_degrees: float = 85.0
