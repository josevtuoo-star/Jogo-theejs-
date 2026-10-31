# Sobrevivência — Protótipo 0.2 (Godot 4, Android)

Protótipo focado em **jogabilidade, mecânicas, personagem, animações e física**, num pátio de
treino com circuito de parkour.

## Como abrir no celular (Godot para Android)

1. Instale o **Godot Engine 4** (versão 4.3 ou mais nova) pela Play Store ou pelo site
   godotengine.org.
2. Copie a pasta `godot/` (ou o arquivo `.zip` do projeto) para o celular.
3. No Godot: **Importar** → escolha o `project.godot` (ou o `.zip`) → **Importar e editar**.
4. Na primeira vez ele importa o personagem, as texturas, o céu e os sons (leva alguns segundos).
5. Aperte **▶ (Executar projeto)**.

No PC funciona igual (Godot 4.3+ para Windows/Linux/Mac).

## Controles

| Ação | Celular | PC | Controle |
| --- | --- | --- | --- |
| Andar | analógico (lado esquerdo; aparece onde o dedo encostar). Pouco = anda, todo = trota | WASD / setas | analógico esquerdo |
| Correr | empurre o dedo **além do anel externo** do analógico | Shift | apertar o analógico esquerdo |
| Olhar | arraste no lado direito da tela | mouse (clique para prender, Esc solta) | analógico direito |
| Pular / parkour | **PULAR** — o botão vira **SALTAR**, **SUBIR** ou **ESCALAR** quando há obstáculo à frente | Espaço | A |
| Agachar / deslizar | **AGACHAR** (liga/desliga); correndo vira **DESLIZAR**; pendurado vira **SOLTAR** | C ou Ctrl | B |
| Soco (combo) | **SOCO** — toque de novo no ritmo: jab → direto → gancho | clique esquerdo ou F | X |
| Chute | **CHUTE** | botão direito do mouse ou G | RB |
| 1ª / 3ª pessoa | **1ª/3ª** (canto superior direito) | V | Y |
| Recomeçar | **↺** | R | Select |

No PC, **F1** mostra os controles de toque.

## Parkour

| Movimento | Como fazer |
| --- | --- |
| **Subir** em obstáculo de 0,45 a 1,45 m | chegue perto e aperte PULAR (o botão mostra SUBIR) |
| **Saltar por cima** de muro fino (até 1,25 m) | venha correndo e aperte PULAR (mostra SALTAR) — passa por cima sem parar |
| **Agarrar a borda** de paredes altas (até ~3,4 m) | pule de frente para a parede: as mãos agarram a borda e ele fica **pendurado** |
| **Subir** estando pendurado | PULAR ou empurre o analógico para a frente; **SOLTAR** (agachar) ou para trás larga |
| Subir paredes de ~2 m | pule de frente: ele já sobe direto, sem ficar pendurado |
| **Deslizar** | correndo, aperte AGACHAR: passa embaixo da barra de 1,0 m; dá para pular saindo do deslize |
| **Rolamento** | ao cair de mais de ~3 m em movimento ele rola e segue correndo (ou aperte AGACHAR no ar antes de cair) |
| Aterrissagem pesada | caindo de alto parado, ele amortece agachando e demora um instante para levantar |

## O que tem neste protótipo

**Personagem e animações** — 31 animações misturadas por uma `AnimationTree` montada no
código (`scripts/player.gd`):
- andar, trotar e correr (e andar de lado/para trás em 1ª pessoa) **reamostradas para o mesmo
  ciclo e a mesma fase** ao abrir o jogo: a mistura entre elas não "troca de pé" mais, e a
  cadência acompanha a velocidade real (pés sem patinar);
- parado e postura de luta depois de socar; agachado parado e andando;
- pulo parado e **pulo correndo** (pose diferente), aterrissagem leve, pesada e rolamento;
- parkour: subir/saltar obstáculo, pendurado na borda, deslize (entrada, deslizando, saída);
- socos com o corpo todo (jab, direto e **gancho com recuperação** — volta à guarda suave) e
  chute frontal.

**Física**
- peso e inércia: acelera e freia; quanto mais rápido, mais aberta é a curva; meia-volta
  correndo primeiro freia;
- ladeira: subindo fica mais lento, descendo embala um pouco; deslizando ladeira abaixo ganha
  velocidade e no plano o atrito freia;
- pulo com "tempo de coiote", memória do botão e altura variável (segurar = mais alto);
- agachar muda o tamanho da colisão (túnel de 1,35 m; não levanta embaixo do teto);
- **o peso do personagem (75 kg) é aplicado no que está sob os pés** — a gangorra desce com
  ele; empurra caixas, barris e bolas andando contra elas (bola leve sai rolando, pilha pesada
  anda devagar);
- soco e chute acertam o que estiver na frente na hora do impacto (jab 12, direto 18, gancho 26,
  chute 42 N·s), com faíscas, tremida da câmera, som e micro-pausa ("hitstop");
- saco de pancada pendurado por junta física, gangorra com dobradiça, 18 dominós em curva.

**Câmeras**
- 3ª pessoa acima do ombro, com braço de câmera que não atravessa paredes;
- **1ª pessoa estilo bodycam**: lente grande-angular olho de peixe, aberração cromática nas
  bordas, vinheta da lente, cor fria/lavada de câmera de corpo, letreiro **● REC** com data e
  hora do aparelho; a câmera vai na cabeça e balança/inclina com o tronco (corrida, pulo,
  rolamento); você vê seus braços, pernas e as mãos agarrando a borda; nunca atravessa parede.

**Gráficos e luz**
- céu real em foto 360° (HDRI) que também ilumina e reflete no cenário, sol na mesma direção do
  sol da foto, sombras suaves, tom ACES, neblina leve de distância;
- chão de terra e grama com textura em duas escalas misturadas (sem "azulejo" repetido), muro de
  tijolos com relevo, caixas de madeira, concreto procedural (manchas, poros e relevo sem
  textura) nos blocos;
- correção de cor final (contraste, saturação, vinheta) em todas as câmeras.

**Mapa (60 × 60 m)**: circuito de parkour (muro de 0,6 m, muros de 1,0 e 1,2 m para saltar,
bloco de 1,4 m, paredão de 3,3 m, torre de 5 m), paredão de 3,0 m para pendurar, barras para
deslizar, plataformas de 0,4 a 2,0 m, escada com vãos, rampas de 20°/35°/50°, túnel, barreiras,
saco de pancada, caixas, barris, bolas, gangorra e dominós.

## Ajustar

Selecione o nó **Player** em `scenes/main.tscn` (ou abra `scenes/player.tscn`): no Inspetor
estão velocidades, aceleração, pulo/gravidade, atrito do deslize, peso do corpo, força para
empurrar, sensibilidade do olhar e campo de visão das câmeras. Socos e chute (força, alcance,
tempo do impacto) ficam nas tabelas `PUNCHES` e `KICK` no começo de `scripts/player.gd`; a lente
da bodycam fica em `shaders/post.gdshader` (`lens`).

## Arquivos

```
project.godot              configuração (renderizador Compatibility, ideal para Android)
scenes/main.tscn           mapa, céu, luz, HUD, pós-processamento
scenes/player.tscn         personagem (colisão, modelo, câmera)
scripts/player.gd          movimento, física, parkour, socos, câmeras e animações
scripts/touch_controls.gd  analógico, botões (com texto conforme o contexto) e olhar por toque
scripts/inputs.gd          ações de teclado/controle e estado compartilhado
scripts/head_hider.gd      esconde a cabeça em 1ª pessoa
scripts/punching_bag.gd    saco de pancada (contagem e corda)
scripts/main.gd            HUD e letreiro da bodycam
shaders/post.gdshader      bodycam (lente, aberração, vinheta) e correção de cor
shaders/ground.gdshader    chão sem repetição
shaders/concrete.gdshader  concreto procedural
assets/                    personagem com animações, texturas, céu e sons
```

Créditos dos assets em [CREDITOS.md](CREDITOS.md).
