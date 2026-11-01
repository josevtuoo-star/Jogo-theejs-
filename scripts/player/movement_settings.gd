class_name MovementSettings
extends Resource
## Parâmetros físicos do personagem em primeira pessoa.
##
## Todos os valores usam unidades do SI (metros, segundos, quilogramas,
## newtons). Os padrões foram calibrados a partir de dados reais de
## locomoção humana e ajustados para controle confortável em touchscreen.

@export_group("Velocidades (m/s)")
## Caminhada normal. Um adulto caminha entre 1,3 e 1,8 m/s; o jogo usa um
## valor um pouco maior para não ficar arrastado.
@export_range(0.5, 6.0, 0.05) var walk_speed: float = 2.6
## Corrida sustentada (jogging rápido). Consome resistência.
@export_range(2.0, 10.0, 0.05) var sprint_speed: float = 5.4
## Deslocamento agachado.
@export_range(0.3, 4.0, 0.05) var crouch_speed: float = 1.25
## Multiplicador aplicado ao andar de lado.
@export_range(0.1, 1.0, 0.01) var strafe_multiplier: float = 0.85
## Multiplicador aplicado ao andar para trás.
@export_range(0.1, 1.0, 0.01) var backward_multiplier: float = 0.65
## Perda de velocidade em subida. 0 = nenhuma; 1 = o seno da inclinação é
## subtraído integralmente da velocidade.
@export_range(0.0, 1.0, 0.01) var uphill_penalty: float = 0.55

@export_group("Aceleração e inércia (m/s²)")
## Aceleração no chão em direção à velocidade desejada.
@export_range(1.0, 60.0, 0.5) var ground_acceleration: float = 11.0
## Frenagem no chão quando o jogador solta o direcional ou reduz a velocidade.
@export_range(1.0, 80.0, 0.5) var ground_deceleration: float = 14.0
## Atrito lateral ao mudar de direção no chão (quanto maior, mais rápida a curva).
@export_range(1.0, 80.0, 0.5) var ground_turn_friction: float = 16.0
## Controle no ar. Pequeno, para preservar o momento do salto.
@export_range(0.0, 20.0, 0.1) var air_acceleration: float = 1.6
## Arrasto horizontal no ar.
@export_range(0.0, 10.0, 0.05) var air_drag: float = 0.15

@export_group("Salto e queda")
## Altura máxima do centro de massa no salto em pé (metros).
@export_range(0.1, 2.0, 0.01) var jump_height: float = 0.55
## Fração da altura do salto quando a resistência está insuficiente.
@export_range(0.0, 1.0, 0.01) var exhausted_jump_factor: float = 0.5
## Tempo após sair de uma borda em que o salto ainda é aceito.
@export_range(0.0, 0.5, 0.01) var coyote_time: float = 0.12
## Tempo em que um toque de salto é lembrado antes de tocar o chão.
@export_range(0.0, 0.5, 0.01) var jump_buffer_time: float = 0.12
## Intervalo mínimo entre aterrissar e saltar de novo (impede "bunny hop").
@export_range(0.0, 2.0, 0.01) var jump_cooldown: float = 0.35
## Velocidade terminal de queda livre de um corpo humano (~55 m/s).
@export_range(10.0, 90.0, 0.5) var terminal_velocity: float = 55.0
## Impacto vertical até o qual não há dano (7,7 m/s ≈ queda de 3 m).
@export_range(1.0, 30.0, 0.1) var safe_impact_speed: float = 7.7
## Impacto vertical que causa dano letal (17,1 m/s ≈ queda de 15 m).
@export_range(2.0, 60.0, 0.1) var lethal_impact_speed: float = 17.1
## Dano causado por um impacto letal (escala do sistema de vida).
@export_range(1.0, 1000.0, 1.0) var lethal_fall_damage: float = 100.0
## Impacto a partir do qual a aterrissagem reduz temporariamente a velocidade.
@export_range(1.0, 30.0, 0.1) var stagger_impact_speed: float = 4.5
## Duração máxima da redução de velocidade após uma aterrissagem forte.
@export_range(0.0, 3.0, 0.01) var stagger_max_duration: float = 0.9
## Multiplicador de velocidade mínimo durante a recuperação da aterrissagem.
@export_range(0.0, 1.0, 0.01) var stagger_min_speed_multiplier: float = 0.35

@export_group("Corpo")
## Massa do sobrevivente com roupas, usada para empurrar objetos e pisar neles.
@export_range(30.0, 200.0, 0.5) var body_mass: float = 80.0
## Força horizontal máxima que o personagem consegue aplicar empurrando.
@export_range(0.0, 3000.0, 10.0) var max_push_force: float = 650.0
@export_range(0.15, 0.6, 0.01) var capsule_radius: float = 0.3
@export_range(1.0, 2.4, 0.01) var standing_height: float = 1.8
@export_range(0.6, 1.6, 0.01) var crouch_height: float = 1.15
## Distância entre o topo da cabeça e a linha dos olhos.
@export_range(0.0, 0.3, 0.01) var eye_offset_from_top: float = 0.12
## Velocidade (m/s) com que a altura do corpo muda ao agachar/levantar.
@export_range(0.5, 10.0, 0.05) var crouch_transition_speed: float = 3.2

@export_group("Terreno")
## Inclinação máxima caminhável (graus).
@export_range(0.0, 89.0, 0.5) var max_floor_angle_degrees: float = 46.0
## Distância de "grudar" no chão ao descer degraus e rampas.
@export_range(0.0, 1.0, 0.01) var floor_snap_length: float = 0.35
## Altura máxima de degrau que o personagem sobe sem saltar.
@export_range(0.0, 0.6, 0.01) var max_step_height: float = 0.32

@export_group("Passada")
## Comprimento de um passo andando (m). Controla o ritmo dos passos e do balanço de câmera.
@export_range(0.2, 2.0, 0.01) var walk_stride: float = 0.72
@export_range(0.2, 3.0, 0.01) var sprint_stride: float = 1.15
@export_range(0.2, 2.0, 0.01) var crouch_stride: float = 0.5

@export_group("Resistência")
## Consumo de resistência por segundo correndo.
@export_range(0.0, 100.0, 0.5) var sprint_stamina_drain: float = 11.0
## Custo de resistência de um salto.
@export_range(0.0, 100.0, 0.5) var jump_stamina_cost: float = 14.0

@export_group("Visão")
## Limite do olhar para cima/baixo (graus).
@export_range(45.0, 89.9, 0.1) var max_pitch_degrees: float = 85.0
