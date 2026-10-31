# Jogo-theejs- — Sobrevivência

> **O projeto passou para o Godot 4 (Android).** O protótipo novo está na pasta
> [`godot/`](godot/) — veja [godot/README.md](godot/README.md). O jogo em Three.js abaixo
> fica guardado só como referência.

## Versão antiga em Three.js

Jogo de sobrevivência em primeira pessoa (estilo DayZ / Minecraft / The Walking Dead) feito com **Three.js**, rodando direto no navegador em **PC e Android**. Não precisa instalar nada nem compilar: o Three.js é carregado por CDN.

## Versão 0.01 (protótipo) — mapa aberto

### Movimento e física (realistas)
- **Andar** 1,7 m/s, **trotar** 3,6 m/s (padrão), **correr** 6,2 m/s, agachado 1,3 m/s; de costas e de lado mais devagar
- **Inércia**: o corpo leva um tempo para ganhar e perder velocidade; no ar quase não muda de direção
- Ladeira acima é mais lento; pouso forte faz o personagem amortecer e perder velocidade
- Gravidade e pulo realistas (~0,65 m); dano de queda a partir de ~3 m
- Correr sem limite (a respiração fica ofegante depois de correr bastante); fôlego, fome e sede ficaram guardados para depois
- **Deslizar** (agachar correndo) e **rolamento** (agachar antes de cair)
- **Parkour**: passar por cima (cercas), salto rápido correndo, apoiar as mãos e subir (caixotes, barris), escalada alta (até ~2,1 m), **agarrar bordas no ar e ficar pendurado** (andar de lado, subir ou soltar)
- **Escadas de mão**, **inclinar/espiar** (`Q`/`E`), **subir degraus baixos** sozinho
- **Água**: andar na parte rasa, nadar, mergulhar, subir no píer
- Colisões com cápsula + Octree (paredes, rampas, escadas, teto, portas); o **relevo colide pela grade de alturas** (a mesma que desenha o chão), bem mais leve

### Personagem e animações
- **Personagem “enemy”** (CC BY 4.0): balaclava, blusa, calça tática, coturno, coldre — com a **pistola dele** (ferrolho, carregador, gatilho e bala separados)
- **Animações do próprio arquivo** (separadas do clipe único): parado, arma pronta, corrida, andar mirando, agachado mirando, mirando parado
- **Animações públicas** (Mesh2Motion, CC0) convertidas para o esqueleto dele para o que faltava: andar, correr, de costas, de lado, agachado, furtivo, pulo, pouso, rolar, deslizar, nadar, escada, escalar borda, pendurado, socos, recarga de pistola, pegar, comer/beber, revistar ajoelhado, dano, morte, ferido, cansado
- Clipes divididos em **pernas** e **tronco**: mirar, atirar, recarregar, golpear, comer/beber e curativo trocam só a parte de cima; as pernas continuam andando
- **Mira de verdade**: mirando, o tronco gira até o cano apontar para o centro da tela; o tiro tem recuo no braço, ferrolho voltando, cápsula ejetada, clarão
- Escada, nado, pendurado e curativo: a pistola vai para o **coldre da coxa**
- Câmera de 1ª pessoa estilo **GoPro** presa na cabeça (grande-angular, distorção de lente, balanço da cabeça); 3ª pessoa com `V`

### Menu, configurações e HUD
- **Menu inicial em tela cheia**: SOBREVIVÊNCIA SOLO, ONLINE (em breve), CONFIGURAÇÕES, CONTROLES; na pausa vira CONTINUAR / SAIR PARA O MENU
- **Configurações em abas**: Gráficos (qualidade, distância de visão, campo de visão, brilho, lente GoPro, balanço, antisserrilhado, FPS), Controles (sensibilidade, inverter Y, vibração), Áudio, HUD
- **Editor de HUD**: arraste cada botão e elemento (ATIRAR, MIRAR, joystick, barra de vida, bússola, itens, munição...) para onde quiser e ajuste **tamanho** e **opacidade** de cada um; restaurar um ou todos; fica salvo no aparelho
- Opacidade geral do HUD e tamanho geral dos botões

### Itens e saque
- **Curativo** (+40 de vida, `1` ou barra de itens) com animação e som
- **Revistar** (`F`): armários, geladeiras, caixas, porta-malas, armários militares, barracas e mochilas — dá curativos e munição (cada lugar uma vez)
- Pistola 9mm: 15 no carregador + reserva; caixas de munição pelo mapa

### Mapa (1,2 km × 1,2 km)
- **Vilarejo** central (o original), **Vila Leste** e **Vila Oeste** (casas com portas que abrem, janelas, telhado de duas águas, móveis, mercado), **Fazenda** (casa, celeiro grande, silo, cercas, fardos), **Bloqueio militar** (sacos de areia, contêineres, barracas, torre de vigia com escada), **Engavetamento** na estrada, **Torre de rádio** (24 m, plataforma com escada) e **Cabanas** na mata com fogueira
- Estradas ligando tudo, morros grandes, serras na borda, matas fechadas e campos abertos, lago
- **Otimização**: árvores em blocos de 120 m (descartados fora da tela e de longe); construções fundidas por material em blocos de 40 m; **grama num único desenho** que acompanha o jogador e lê o relevo de uma textura; terreno, troncos e pedras fora do Octree (colisão por grade de alturas e por círculos) — no teste o carregamento caiu de 41 s para 9 s; no celular começa em qualidade média, sem MSAA

### Gráficos e iluminação
- **Ciclo de dia e noite** (1 min = 1 h; a noite passa mais rápido): sol andando com luz dourada no entardecer, noite com luar forte (dá para enxergar), estrelas e lua; fumaça e poeira escurecem à noite, céu, nuvens e neblina mudando de cor, reflexos do céu escurecendo à noite; relógio no topo
- **Gradação de cor** na passada final (saturação, curva S, noite fria, fim de tarde quente), nitidez adaptativa, MSAA, sem granulado; sombra do sol cobrindo mais área

### Som
- **Espacialização HRTF** (fones de ouvido: dá para saber de onde vem), **absorção do ar** (longe = sem agudos), **oclusão** (parede ou morro no caminho abafa e abaixa o som)
- **Dois reverbs**: sala (dentro de casa) e exterior (reflexões do vale e da mata, cauda longa — o tiro ecoa)
- Ambiente que muda com a hora: pássaros de dia, grilos de noite; corvos e **tiroteios ao longe** de vez em quando
- Passos por piso, roupa e equipamento, respiração ofegante depois de correr, coração com pouca vida, carregador saindo/entrando, ferrolho, cápsulas tilintando, portas, impactos por material

### Controles

| Ação | PC | Android | Controle |
|---|---|---|---|
| Mover / olhar | `W A S D` + mouse | Joystick + arrastar à direita | Analógicos |
| Correr / andar devagar | `Shift` / `X` | **CORRER**, joystick no limite ou **corrida travada** | `L3` |
| Mirar / atirar / recarregar | Botão direito / clique / `R` | **MIRAR** / **ATIRAR** / **RECARR.** | `LT` / `RT` / `↓` |
| Golpe (jab / coronhada) | `G` ou botão do meio | **GOLPE** | `LB`+`RB` |
| Curativo | `1` | Barra de itens | `↑` |
| Usar / porta / revistar | `F` | **USAR** | `X` |
| Pular / escalar | `Espaço` | **PULAR** | `A` |
| Agachar / deslizar / rolar | `C` / `Ctrl` | **AGACHAR** | `B` |
| Espiar | `Q` / `E` | — | `LB` / `RB` |
| 1ª (GoPro) / 3ª pessoa | `V` | 👁 | `Y` |
| Pausar | `Esc` | ❚❚ | `Start` |

No Android o jogo entra em tela cheia e tenta travar na horizontal.

## Como rodar

Os módulos JavaScript precisam ser servidos por HTTP (abrir o `index.html` direto com `file://` não funciona).

**GitHub Pages (mais fácil para jogar no celular):** em *Settings → Pages*, escolha a branch e a pasta `/ (root)`. O jogo fica em `https://<usuario>.github.io/Jogo-theejs-/`.

**Localmente:**

```bash
python3 -m http.server 8080
# ou: npx serve .
```

Abra `http://localhost:8080`. Para testar no celular na mesma rede Wi‑Fi, use `http://<ip-do-pc>:8080`.

## Estrutura

```
index.html          página, HUD, menu e botões touch
css/style.css       estilos (HUD, menu, controles touch)
js/main.js          renderizador, loop do jogo, menu/pausa
js/input.js         teclado, mouse, joystick virtual e toque
js/player.js        física do personagem (cápsula, pulo, agachar, deslizar, escalar, escadas, rolar, dano)
js/cameraRig.js     câmera GoPro (1ª pessoa, presa na cabeça) e câmera em 3ª pessoa
js/character.js     personagem: clipes (pernas/tronco), mira (tronco aponta o cano), tiro, recarga, golpes, itens, coldre
js/pois.js          lugares do mapa: vilas, fazenda, bloqueio militar, engavetamento, torre de rádio, cabanas, pontos de saque
js/hudEditor.js     editor de HUD (posição, tamanho e opacidade de cada botão/elemento)
js/lens.js          passada final: lente de GoPro, nitidez adaptativa, tom e antisserrilhado
js/modelLoader.js   carrega os modelos 3D (.glb, ou glTF .json + geometria em texto no artifact)
js/world.js         mapa, céu, iluminação, relevo, vegetação e malha de colisão
js/effects.js       partículas: poeira, fumaça, brasas, folhas caindo, fogueira
js/physics.js       objetos soltos com física (latas, garrafas, baldes...)
js/dummies.js       bonecos de treino (balanço com mola, marcas de corte e furos)
js/textures.js      texturas procedurais (canvas)
js/photoAssets.js   texturas fotográficas, material do terreno (mistura por altura) e céu HDRI
js/icons.js         ícones SVG dos botões touch
js/trees.js         copas de árvore com cartões de galhos/folhas (texturas desenhadas em canvas)
assets/             sons gravados (sfx/), texturas (tex/), céu HDRI (env/) e CREDITS.md
models/             personagem.glb (personagem + pistola + animações)
js/audio.js         sons procedurais (Web Audio)
```

No console do navegador, `window.game` dá acesso ao jogador e ao mundo para depuração.

## Próximas etapas (sugestão)

2. Inventário e itens no chão (coletar)
3. Fome, sede e temperatura
4. Zumbis com IA (patrulha, perseguição, ataque)
6. Construção e coleta de recursos (estilo Minecraft)
7. Ciclo dia/noite e salvamento

## Créditos dos sons, texturas, céu e animações

Gravações reais (Kenney, The Free Firearm Sound Library, Shotgun Reload Sound Effects — CC0;
Godot demos — MIT), texturas fotográficas do Poly Haven (CC0) e do three.js (MIT), céu HDRI do
Poly Haven (CC0) e animações do Mesh2Motion (CC0). Lista completa, com links e o que foi alterado em cada arquivo:
[`assets/CREDITS.md`](assets/CREDITS.md).

## Créditos dos modelos 3D

- [“enemy”](https://sketchfab.com/3d-models/enemy-15557449d29144c49e02942d87c7316f) por **DJMaesen** — CC BY 4.0 (personagem, pistola e as animações dele)
- Animações extras: biblioteca do [Mesh2Motion](https://github.com/Mesh2Motion/mesh2motion-app) — CC0
