# Sobrevivência — v0.01 (primeiro protótipo jogável)

Jogo de sobrevivência no estilo DayZ / The Walking Dead / Minecraft, feito no **Godot 4**
para **Android** (funciona também no PC). Este protótipo foi montado do zero usando **apenas a
Universal Animation Library (Standard) do Quaternius** (personagem manequim + 43 animações,
CC0). Todo o resto — mapa, materiais, céu, sons, controles — é gerado por código.

## Como abrir

1. Instale o **Godot Engine 4** (4.3 ou mais novo) — no Android pela Play Store, ou no PC.
2. No Godot: **Importar** → escolha o `project.godot` (ou o `.zip` do projeto) → **Importar e editar**.
3. Na primeira vez ele importa o personagem e as animações (alguns segundos).
4. Aperte **▶ (Executar projeto)**.

## Controles

| Ação | Celular | PC | Controle |
| --- | --- | --- | --- |
| Andar | analógico (lado esquerdo; aparece onde o dedo encostar). Pouco = anda, todo = trota | WASD / setas | analógico esquerdo |
| Correr | empurre o dedo **além do anel externo** | Shift | apertar o analógico esquerdo |
| Olhar | arraste no lado direito da tela | mouse (clique prende, Esc solta) | analógico direito |
| Pular / nadar mais rápido | **PULAR** (segure para pular mais alto) | Espaço | A |
| Agachar / rolar | **AGACHAR** (liga/desliga); correndo vira **ROLAR** | C ou Ctrl | B |
| Usar | **USAR** — o botão mostra a ação: **PEGAR**, **SENTAR**, **ABRIR PORTÃO**, **LEVANTAR** | E | Y |
| Soco (combo) | **SOCO** — toque de novo no ritmo: jab → direto | clique esquerdo ou F | X |
| 1ª / 3ª pessoa | **1ª/3ª** (canto superior direito) | V | analógico direito (apertar) |
| Recomeçar | **↺** | R | Select |

No PC, **F1** mostra os controles de toque.

## O que dá para fazer

- **Andar, trotar e correr** com peso: acelera, freia, faz curva mais aberta correndo, sobe
  ladeira mais devagar. As animações de andar/trotar/correr são sincronizadas (sem trocar de
  pé ao misturar) e a cadência acompanha a velocidade real.
- **Agachar** (passa no túnel de 1,3 m e não levanta embaixo do teto), **pular** (tempo de
  coiote, memória do botão, altura variável) e **rolar** (correndo + agachar, ou ao cair de
  mais de ~3 m em movimento; parado, a queda alta vira uma aterrissagem pesada).
- **Nadar** no lago: entre pela rampa; onde não dá pé ele boia e nada; volta a andar quando
  o fundo fica raso. Na água rasa anda mais devagar, com som de água.
- **Empurrar**: a caixa pesada (60 kg) é empurrada com as duas mãos (animação de empurrar);
  caixas leves, barris e bolas são empurrados andando contra eles. O peso do personagem
  (75 kg) é aplicado no que está sob os pés.
- **Socar** (jab e direto em combo): empurra objetos com física, saco de pancada pendurado
  que balança e conta os golpes, faíscas, tremida e micro-pausa no impacto.
- **USAR**: pegar **suprimentos** nas mesas (animação de pegar; contador no HUD), **sentar**
  no banco (sentar, sentado, levantar), apertar o **botão do painel** que abre/fecha o
  portão de correr da garagem (o personagem dá um passo até alcançar com a mão).
- **Câmeras**: 3ª pessoa por cima do ombro (não atravessa paredes) e 1ª pessoa nos olhos
  (corpo visível, balanço do passo estabilizado, nunca entra na parede).
- **Corpo procedural** por cima das animações: pés apoiados no chão em escadas e rampas (IK),
  quadril acompanhando o terreno, tronco e cabeça olhando para onde a câmera aponta,
  inclinação nas curvas; em 1ª pessoa as pernas seguem a direção do passo (de lado e de ré).

## Mapa de testes (60 × 60 m)

Gramado com manchas de terra, lago com rampa e fundo de 2,2 m, garagem com portão e
painel, três mesas com cinco suprimentos, banco, saco de pancada, pilha de caixas, caixa
pesada, barris, bolas, blocos de 0,5/1,0/1,5 m, rampa de 20°, escada, túnel baixo e
árvores. Céu, luz do sol com sombras e neblina leve.

## Arquivos

```
project.godot               configuração (renderizador Compatibility, ideal para Android)
assets/ual/                 Universal Animation Library (personagem + animações) e licença
scenes/main.tscn            mapa, céu, luz, HUD
scenes/player.tscn          personagem (colisão, modelo, câmera)
scripts/player.gd           movimento, física, ações, nado, socos, câmeras e animações
scripts/procedural_body.gd  pés no chão (IK), inclinação, olhar, cabeça oculta em 1ª pessoa
scripts/touch_controls.gd   analógico, botões com texto conforme o contexto, olhar por toque
scripts/inputs.gd           ações de teclado/controle e estado compartilhado
scripts/sfx.gd              sons gerados por código
scripts/supply.gd, bench.gd, gate.gd, gate_button.gd, water.gd, punching_bag.gd   objetos
scripts/main.gd             HUD
shaders/                    grama, concreto, madeira, água, azulejo e cor final
```

## Ajustar

Selecione o nó **Player** em `scenes/main.tscn` (ou abra `scenes/player.tscn`): no Inspetor
ficam velocidades (andar, trotar, correr, agachado, nadando, empurrando), aceleração,
pulo/gravidade, força para empurrar, peso do corpo, sensibilidade do olhar e as câmeras.

## Créditos

- Personagem e animações: **Universal Animation Library (Standard)** —
  [Quaternius](https://quaternius.com), licença **CC0** (veja `assets/ual/License.txt`).
- Todo o resto (código, mapa, materiais procedurais, sons sintetizados): feito para este projeto.
