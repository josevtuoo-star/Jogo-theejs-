# Sobrevivência — Protótipo 0.1 (Godot 4, Android)

Primeiro protótipo focado em **jogabilidade, mecânicas, personagem, animações e física**, num
mapa pequeno de testes.

## Como abrir no celular (Godot para Android)

1. Instale o **Godot Engine 4** (versão 4.3 ou mais nova) pela Play Store ou pelo site
   godotengine.org.
2. Copie a pasta `godot/` (ou o arquivo `.zip` do projeto) para o celular.
3. No Godot: **Importar** → escolha o `project.godot` (ou o `.zip`) → **Importar e editar**.
4. Na primeira vez ele importa o personagem e os sons (leva alguns segundos).
5. Aperte **▶ (Executar projeto)**.

No PC funciona igual (Godot 4.3+ para Windows/Linux/Mac).

## Controles

| Ação | Celular | PC | Controle |
| --- | --- | --- | --- |
| Andar | analógico (lado esquerdo; aparece onde o dedo encostar). Pouco = anda, todo = trota | WASD / setas | analógico esquerdo |
| Correr | empurre o dedo **além do anel externo** do analógico | Shift | apertar o analógico esquerdo |
| Olhar | arraste no lado direito da tela | mouse (clique para prender, Esc solta) | analógico direito |
| Pular | **PULAR** (segure para pular mais alto) | Espaço | A |
| Agachar / levantar | **AGACHAR** (liga/desliga) | C ou Ctrl | B |
| Soco (combo) | **SOCO** — toque de novo no ritmo para emendar jab → direto → gancho | clique esquerdo ou F | X |
| 1ª / 3ª pessoa | **1ª/3ª** (canto superior direito) | V | Y |
| Recomeçar | **↺** | R | Select |

No PC, **F1** mostra os controles de toque (para testar com o mouse/tela touch).

## O que tem neste protótipo

**Personagem e animações** — 20 animações misturadas por uma `AnimationTree` montada no
código (`scripts/player.gd`):
- parado, andar, trotar e correr misturados pela velocidade; a animação acelera ou desacelera
  para os pés não "patinarem" no chão;
- em 1ª pessoa o corpo fica de frente para onde você olha, então também anda de lado e para
  trás com as animações certas;
- agachado parado e andando (transição suave), pulo (impulso, no ar, aterrissagem — queda
  pequena só dobra os joelhos, queda alta agacha fundo e segura o personagem um instante);
- combo de socos com o corpo inteiro (jab, direto e gancho) e postura de luta depois de socar.

**Física e mecânicas**
- aceleração e frenagem (o personagem tem peso; no ar dá para corrigir só um pouco);
- pulo com "tempo de coiote" (ainda pula logo depois de sair da borda), memória do botão
  (apertou um pouco antes de cair, pula ao tocar o chão) e altura variável;
- agachar muda o tamanho da colisão: passa no túnel de 1,35 m e **não deixa levantar** embaixo
  do teto;
- sobe escadas (rampa invisível por baixo dos degraus) e rampas até 46°; mais íngreme escorrega;
- empurra caixas, barris e bolas andando contra elas (bola leve sai rolando, pilha pesada
  anda devagar);
- o soco acerta o que estiver na frente na hora do impacto e empurra com força (jab 12, direto
  18, gancho 26 N·s), com faíscas, tremida da câmera, som de impacto e uma micro‑pausa
  ("hitstop") para dar peso ao golpe;
- saco de pancada pendurado por uma junta física: balança e conta os golpes.

**Câmeras**
- 3ª pessoa acima do ombro, com braço de câmera que não atravessa paredes;
- 1ª pessoa presa à cabeça animada (balança naturalmente com o passo), cabeça escondida e o
  resto do corpo visível — olhando para baixo você vê pernas e braços; socos aparecem na tela;
- troca suave entre as duas; o campo de visão abre um pouco ao correr.

**Mapa de testes** (50 × 50 m): plataformas de 0,4 a 2,0 m (altura do pulo), escada com área
alta e vãos de 1,2 / 2,0 / 3,0 m (o último só correndo), rampas de 20°, 35° e 50°, túnel baixo,
barreiras de 0,3 / 0,6 / 0,9 m, pilha de caixas, barris, bolas e o saco de pancada.

**Sons**: passos no ritmo da passada (mais fortes correndo, baixos agachado), aterrissagem,
roupa ao pular/socar, impactos de soco.

## Ajustar

Selecione o nó **Player** em `scenes/main.tscn` (ou abra `scenes/player.tscn`): no Inspetor
estão as velocidades, aceleração, altura/gravidade do pulo, força para empurrar, sensibilidade
do olhar e distância/campo de visão das câmeras. Os socos (força, alcance, tempo do impacto)
ficam na tabela `PUNCHES` no começo de `scripts/player.gd`.

## Arquivos

```
project.godot           configuração (renderizador Compatibility, ideal para Android)
scenes/main.tscn        mapa de testes, luz, céu, HUD
scenes/player.tscn      personagem (colisão, modelo, câmera)
scripts/player.gd       movimento, física, pulo, agachar, socos, câmeras e animações
scripts/touch_controls.gd  analógico, botões e olhar por toque (multitoque)
scripts/inputs.gd       ações de teclado/controle e estado compartilhado
scripts/head_hider.gd   esconde a cabeça em 1ª pessoa
scripts/punching_bag.gd saco de pancada (contagem e corda)
shaders/grid.gdshader   material de protótipo em grade
assets/                 personagem com animações e sons
```

Créditos dos assets em [CREDITOS.md](CREDITOS.md) (tudo CC0).
