# Etapa 3 — Animações em primeira pessoa

> **Substituído na etapa 4:** os braços procedurais e o `FirstPersonAnimator` descritos aqui deram lugar ao corpo humano completo, às animações de captura retargetadas e ao `BodyAnimator` (veja [`ETAPA_04_RECONSTRUCAO.md`](ETAPA_04_RECONSTRUCAO.md)). Vida, lesões, interação, combate por evento de quadro e morte continuam valendo.

Braços e mãos animados, sincronizados com a física real do personagem. A etapa inclui os sistemas que as animações precisam para existir de verdade: vida e ferimentos, lesão nas pernas, interação, combate corpo a corpo, morte e renascimento.

## Por que animações próprias

A pesquisa de assets (detalhes em [`ASSET_LICENSES.md`](../ASSET_LICENSES.md)) encontrou:

- **Mixamo:** os termos proíbem redistribuir os arquivos brutos, e o repositório é público. **Rejeitado.**
- **Quaternius Universal Animation Library 1 e 2:** CC0, verificado. São animações genéricas de corpo inteiro em terceira pessoa: na câmera em primeira pessoa os braços ficam fora do quadro ou em ângulos sem sentido. **Catalogadas** para o corpo inteiro e os zumbis das próximas etapas, e não usadas aqui.
- **Braços em primeira pessoa com licença livre:** só existem rigs sem animação (OpenGameArt, CC0, `.blend`/`.fbx`).

Por isso, a solução definitiva é um rig próprio, com animações autorais escritas para a câmera deste jogo.

## Rig

Gerado por `tools/build_fp_arms.gd`:

- **Esqueleto:** 19 ossos com nomes do `SkeletonProfileHumanoid` do Godot. Para cada lado: `UpperArm`, `LowerArm`, `Hand`, polegar (2), indicador (2) e médio (2), mais `Root`. Anelar e mínimo seguem o médio.
- **Malha com skin:**
  - mangas de jaqueta com punho;
  - mão com palma e quatro dedos mais o polegar;
  - pesos suaves nas articulações;
  - 2 materiais.
- **Shader do viewmodel** (`resources/materials/viewmodel.gdshader`):
  - comprime a profundidade para perto da câmera, então os braços nunca atravessam paredes, sem segunda câmera;
  - não projeta sombra;
  - tecido com trama e desgaste.
- **Tamanho no APK:** malha de 54 KB e biblioteca de 357 KB.

## Animações (19)

São escritas como **intenção física**: posição do punho, orientação da mão e quanto os dedos estão fechados. Depois são convertidas em rotações de osso por **IK analítica de dois ossos** (ombro → cotovelo → punho, cotovelo para fora e para baixo), amostradas a 30 quadros/s com interpolação cúbica.

| Grupo | Animações | Detalhe |
|---|---|---|
| Repouso | `idle`, `crouch_idle` | respiração lenta |
| Locomoção | `walk`, `jog`, `sprint`, `crouch_walk`, `limp_walk` | ciclo normalizado (1 = dois passos); t = 0 é o contato do pé esquerdo com o braço direito à frente (marcha contralateral); arco pendular e atraso das mãos nos contatos |
| Ar | `jump`, `fall` | impulsão e braços abertos para equilíbrio |
| Impactos | `land_soft`, `land_hard` | mãos descem com o corpo; na forte, apoiam |
| Ferimentos | `hurt_light`, `hurt_heavy` | recuo, proteção do rosto, mão no peito |
| Interação | `interact` | alcançar e pressionar; evento `contact` em 0,42 s |
| Combate | `guard`, `attack_light`, `attack_heavy`, `impact_recoil` | jab (evento `hit` em 0,12 s); gancho carregado (segura em 0,30 s, `hit` em 0,43 s); mão rebatida ao acertar parede |
| Morte | `death` | espasmo e braços caindo para fora da visão |

A biblioteca fica no `AnimationPlayer` da cena `fp_arms.tscn` e pode ser aberta no editor. Os eventos e o ponto de "segurar" ficam nos metadados de cada animação (`events`, `hold_time`).

## Animador em camadas

`scripts/animation/fp_animator.gd` (`FirstPersonAnimator`) compõe a pose a cada quadro a partir do estado físico:

1. **Repouso** em tempo real.
2. **Locomoção:**
   - o tempo do ciclo é a **fase da passada física** (`PlayerController.get_gait_phase()`), não um relógio, então o braço acompanha o pé mesmo acelerando, freando ou mancando;
   - a mistura andar → trotar → correr segue a velocidade medida.
3. **Mancar,** pelo grau de lesão das pernas.
4. **Agachado,** pela altura real da cápsula: na transição, o peso é idêntico à fração da altura.
5. **Ar:** impulsão pelo tempo desde o salto e queda pela velocidade vertical.
6. **Guarda** por 2,5 s depois de atacar.
7. **Camadas sobrepostas** (aterrissagem, ferimento, ação e morte):
   - entrada e saída suaves, troca com desvanecimento e máscara por osso (a interação só move o braço direito);
   - eventos de quadro;
   - "segurar" para o golpe carregado.

Usei avaliação manual em vez de `AnimationTree` porque é preciso controlar o tempo pela física e segurar a pose enquanto o jogador carrega o golpe. Custo medido: **~97 µs por quadro** com locomoção, mancar e guarda ativos.

`scripts/animation/viewmodel_motion.gd` (`ViewmodelMotion`) dá massa aos braços, com molas amortecidas:
- atrasam ao girar a visão (até 4°);
- ficam para trás quando o corpo acelera;
- respiram mais forte e mais rápido com a resistência baixa;
- levam um tranco na direção de onde veio o dano.

## Sistemas sincronizados com as animações

| Sistema | Arquivo | Comportamento |
|---|---|---|
| Vida | `scripts/components/health_component.gd` | dano por tipo e direção, morte, renascer; quedas lesionam as pernas (60 de dano = lesão total), que cicatrizam 1%/s |
| Lesão nas pernas | `player_controller.gd` | até −45% de velocidade, sem corrida acima de 50% de lesão, salto menor, animação de mancar |
| Interação | `scripts/player/interaction_component.gd`, `scripts/interaction/*.gd` | raio da câmera (2 m); o efeito acontece no quadro de contato da mão, e só se o objeto ainda estiver ao alcance |
| Combate | `scripts/player/melee_combat.gd` | toque = jab (12 de dano, 9 kg·m/s); segurar = gancho carregado (20–42 de dano, 16–34 kg·m/s); acerto calculado no quadro `hit` por esfera varrida; alvos com `receive_hit(hit)` recebem dano, corpos rígidos recebem impulso, paredes rebatem a mão; exausto, o golpe sai pela metade |
| Morte | `scripts/player/player_death.gd` | a câmera passa a seguir um corpo rígido do tamanho da cabeça, que cai e rola; renascer liberado em 2 s |
| HUD | `scripts/ui/player_hud.gd` | vida, resistência, perna ferida, mira, objeto em foco, clarão de dano, pulsação com vida baixa, tela de morte com a causa |
| Cenário de teste | `tools/build_test_gym.gd` | interruptor com lâmpada, arame farpado (10 de dano/s e metade da velocidade) e boneco de treino que balança e mostra o dano |

## Controles

| Ação | PC | Gamepad | Toque |
|---|---|---|---|
| Atacar (toque) / carregar (segurar) | botão esquerdo do mouse | R1 | ATACAR |
| Interagir / renascer | E | X | USAR |

## Testes

```
godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

**70 + 123 verificações aprovadas no Godot 4.5.1 e no 4.7.1.** A build automática do APK roda as duas baterias e só publica se todas passarem. Os destaques medem o efeito real, não apenas se a animação tocou:

- **Sincronia com a passada:** em todos os contatos do pé esquerdo a mão direita está à frente, e em todos os do pé direito está atrás (trotando e correndo).
- **Amplitude:** andar 70 mm, trotar 150 mm, correr 259 mm.
- **Agachar:** no meio da transição, peso da animação = fração da altura da cápsula (0,574 = 0,574).
- **IK:** o punho chega à posição de autoria (6 mm, que é o balanço respiratório da própria pose).
- **Interação:** a luz acende no quadro 25, o contato da mão em 0,42 s. A 3 m, nada acontece.
- **Soco:**
  - jab: dano no quadro 5;
  - um acerto mesmo apertando de novo durante o golpe;
  - gancho carregado de 70 quadros: dano 40,8, igual ao esperado;
  - caixa derrubada de cima do bloco: 0,11 m, contra 0,13 m da estimativa física;
  - parede: recuo da mão.
- **Ferimentos:** dano 6 dá reação leve, dano 25 dá reação forte com tranco nos braços; a queda não duplica com a reação de ferimento.
- **Morte:** a visão chega ao chão (0,11 m), os controles ficam travados, a tela mostra a causa, e o renascimento restaura vida, câmera e controle.

## Ajustar e criar animações

- **Poses e tempos:** editar `_build_library()` em `tools/build_fp_arms.gd` e rodar `godot --headless --path . --script res://tools/build_fp_arms.gd`. O gerador avisa se algum alvo estiver fora do alcance do braço.
- **Proporções do braço:** constantes `SHOULDER`, `UPPER_LEN`, `FORE_LEN` e `HAND_LEN`.
- **Pesos e velocidades de mistura:** propriedades do nó `FPArms` (animador) e do `ViewModel` (movimento secundário) na cena do jogador.

## Limitações

- **Visual low-poly:** a malha é gerada por código. Quando houver um artista, a malha final pode ser trocada mantendo os mesmos nomes de ossos e a biblioteca de animações.
- **Corpo visível ao olhar para baixo:** ainda não existe. Ele entra com o corpo inteiro (catalogado: Quaternius UAL, CC0) junto com os zumbis.
- **Interação:** a única existente é o interruptor. Pegar itens e abrir portas chegam com o inventário (Etapa 4).
- **Não testado em celular:** como nas etapas anteriores, a validação no aparelho ainda é necessária.
