# Sobrevivência — Protótipo 0.3 (Godot 4, Android)

Jogo de sobrevivência no estilo DayZ / The Walking Dead / Minecraft. Este protótipo foca em
**jogabilidade, mecânicas, personagem, animações e física**, num pátio de treino com circuito de
parkour.

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
| Deitar / rastejar | **DEITAR** (liga/desliga); deitado, PULAR levanta e AGACHAR fica agachado | Z | apertar o analógico direito |
| Soco (combo) | **SOCO** — toque de novo no ritmo: jab → direto → gancho | clique esquerdo ou F | X |
| Chute | **CHUTE** | botão direito do mouse ou G | RB |
| 1ª / 3ª pessoa | **1ª/3ª** (canto superior direito) | V | Y |
| Trocar personagem | **TROCAR** (policial ↔ sobrevivente) | P | — |
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

**Personagens** — dois sobreviventes realistas (texturas de foto) com o mesmo esqueleto e
as mesmas animações: um **policial** (estilo xerife de The Walking Dead) e um **sobrevivente** de
camisa polo e jeans. A malha foi suavizada e os materiais deixados foscos (sem cara de plástico).

**Animações** — 31 animações de captura misturadas por uma `AnimationTree` montada no código
(`scripts/player.gd`), e por cima delas **camadas procedurais** (`scripts/procedural_body.gd`)
que deixam o corpo reagir ao mundo:
- **pés no chão (IK)**: em escada, rampa ou caixa cada pé pousa na altura certa e acompanha a
  inclinação; o quadril desce para o pé mais baixo alcançar (nada de pé flutuando ou
  atravessando o degrau);
- **cabeça e pescoço olham para onde a câmera aponta** (em 3ª e 1ª pessoa);
- **inclinação do tronco** para dentro nas curvas e para frente ao acelerar/correr;
- **girar parado com passinhos**: em 1ª pessoa, parado, a cabeça vira primeiro e, passando de
  ~60°, o corpo gira dando passos (sem deslizar no lugar, como no DayZ);
- andar, trotar e correr reamostradas para o mesmo ciclo e fase (sem troca de pé), cadência
  acompanhando a velocidade real; agachado, **deitado rastejando** (para frente e para trás);
- pulo sem o "afundar" no impulso, pulo correndo, aterrissagens, parkour, socos com o corpo
  todo e chute; a guarda de luta some mais rápido depois de socar.

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
- 3ª pessoa por cima do ombro direito, mais perto (estilo DayZ), com braço de câmera que não
  atravessa paredes; abaixa junto quando agacha ou deita;
- **1ª pessoa realista**: nos olhos do personagem, imagem limpa (sem lente distorcida), campo de
  visão natural (78°); o balanço do passo vem da cabeça animada mas é estabilizado pela metade;
  você vê braços, pernas, os socos e as mãos agarrando a borda; nunca entra na parede.

**Gráficos e luz**
- céu real em foto 360° (HDRI) que também ilumina e reflete no cenário, sol na mesma direção do
  sol da foto, sombras suaves, tom ACES, neblina leve de distância;
- chão de terra e grama com textura em duas escalas misturadas (sem "azulejo" repetido), muro de
  tijolos com relevo, caixas de madeira, concreto procedural (manchas, poros e relevo sem
  textura) nos blocos;
- correção de cor final discreta (contraste, cor levemente fria/dessaturada, vinheta suave).

**Mapa (60 × 60 m)**: circuito de parkour (muro de 0,6 m, muros de 1,0 e 1,2 m para saltar,
bloco de 1,4 m, paredão de 3,3 m, torre de 5 m), paredão de 3,0 m para pendurar, barras para
deslizar, plataformas de 0,4 a 2,0 m, escada com vãos, rampas de 20°/35°/50°, túnel, barreiras,
saco de pancada, caixas, barris, bolas, gangorra e dominós.

## Ajustar

Selecione o nó **Player** em `scenes/main.tscn` (ou abra `scenes/player.tscn`): no Inspetor
estão velocidades (inclusive rastejando), aceleração, pulo/gravidade, atrito do deslize, peso do
corpo, força para empurrar, sensibilidade do olhar e campo de visão das câmeras. Socos e chute (força, alcance,
tempo do impacto) ficam nas tabelas `PUNCHES` e `KICK` no começo de `scripts/player.gd`; a cor
final fica em `shaders/post.gdshader`.

## Arquivos

```
project.godot              configuração (renderizador Compatibility, ideal para Android)
scenes/main.tscn           mapa, céu, luz, HUD, pós-processamento
scenes/player.tscn         personagem (colisão, modelo, câmera)
scripts/player.gd          movimento, física, parkour, socos, câmeras e animações
scripts/touch_controls.gd  analógico, botões (com texto conforme o contexto) e olhar por toque
scripts/inputs.gd          ações de teclado/controle e estado compartilhado
scripts/procedural_body.gd pés no chão (IK), inclinação, cabeça olhando, cabeça oculta na 1ª pessoa
scripts/punching_bag.gd    saco de pancada (contagem e corda)
scripts/main.gd            HUD
shaders/post.gdshader      correção de cor final
shaders/ground.gdshader    chão sem repetição
shaders/concrete.gdshader  concreto procedural
assets/personagens/        policial e sobrevivente (com as animações)
assets/                    texturas, céu e sons
```

Créditos dos assets em [CREDITOS.md](CREDITOS.md).
