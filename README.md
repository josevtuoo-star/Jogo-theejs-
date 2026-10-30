# Jogo-theejs- — Sobrevivência (Three.js)

Jogo de sobrevivência em primeira pessoa (estilo DayZ / Minecraft / The Walking Dead) feito com **Three.js**, rodando direto no navegador em **PC e Android**. Não precisa instalar nada nem compilar: o Three.js é carregado por CDN.

## Etapa 1 — Personagem jogável ✅

### Movimento e física (realistas)
- **Andar** 1,7 m/s, **trotar** 3,6 m/s (padrão), **correr** 6,2 m/s, agachado 1,3 m/s; de costas e de lado mais devagar
- **Inércia**: o corpo leva um tempo para ganhar e perder velocidade; no ar quase não muda de direção
- Ladeira acima é mais lento; pouso forte faz o personagem amortecer e perder velocidade
- Gravidade e pulo realistas (~0,65 m); dano de queda a partir de ~3 m
- Sem barra de fôlego: dá para correr à vontade, mas a respiração fica ofegante depois de correr muito
- **Deslizar** (agachar correndo) e **rolamento** (agachar antes de cair)
- **Parkour**: passar por cima (cercas), salto rápido correndo, apoiar as mãos e subir (caixotes, barris), escalada alta (até ~2,1 m), **agarrar bordas no ar e ficar pendurado** (andar de lado, subir ou soltar)
- **Escadas de mão**, **inclinar/espiar** (`Q`/`E`), **subir degraus baixos** sozinho
- **Água**: andar na parte rasa, nadar, mergulhar, subir no píer
- Colisões com cápsula + Octree (chão, paredes, rampas, escadas, teto, portas)

### Corpo, câmera e animações
- **Personagem**: robô policial (“Cyberpunk Police bot”, CC BY 4.0) com esqueleto Mixamo e pesos de pele próprios; as armas que vinham na mão dele e o pedestal foram tirados
- **Animações prontas** (biblioteca do Mesh2Motion, CC0), convertidas para o esqueleto do robô: parado, andar, trotar, correr, de costas, de lado, agachado parado/andando, andar furtivo, no ar, pouso, rolamento, deslizar, nadar, escada, escalar borda, pendurado, socos, levar dano, morte, ferido
- Os clipes se misturam pela velocidade e direção (frente/trás/lados) com a passada sincronizada; cada clipe é dividido em **pernas** e **tronco/braços**, então os socos e reações trocam só a parte de cima enquanto as pernas continuam andando
- O tronco e a cabeça acompanham o olhar para cima/baixo
- **Câmera de 1ª pessoa estilo GoPro**: presa na cabeça do robô (balança e inclina com a animação), grande-angular com **distorção de lente** e leve escurecimento nas bordas; a cabeça some e o resto do corpo aparece (braços, peito, pernas)
- 3ª pessoa (`V`) com colisão da câmera, sem distorção
- **Zumbi de teste** (“Zombie Walk Test”, CC BY 4.0) andando de lá para cá na estrada, com a animação dele

### Itens e combate
- **Mãos livres** (`1`) ou **pistola Colt M1911 .45** (`2`, rodinha, botão **TROCAR** ou a **barra de armas** na tela)
- **Animações de FPS da pistola** (“FPS pistol animations”, CC BY 4.0): parada, andando, tiro e duas recargas (com bala na câmara e vazia). Os braços do arquivo foram trocados pelos do personagem: as mãos do rig viram alvos de IK para os braços do robô e os **dedos copiam a pegada**; a Colt fica no lugar da pistola do rig, em escala real, com **ferrolho e gatilho** acompanhando o tiro e o **carregador** saindo e entrando na recarga
- **Sacar e guardar** (feitos no jogo): a mão vai até o **coldre na coxa direita**, puxa a Colt e traz num arco até a pose de tiro; a mão esquerda entra no fim; guardar faz o caminho inverso
- **Mirar pela alça e massa** (`botão direito` / **MIRAR** / `LT`) com zoom; correndo, a arma baixa; pendurado, na escada ou nadando ela volta ao coldre e volta para a mão depois
- 7 balas no carregador + reserva; **caixas de munição .45** pelo mapa (`F` para pegar); cápsulas de latão ejetadas que quicam e tilintam no chão; clarão e fumaça
- Bala com dispersão (precisa mirar para acertar longe), furos nas superfícies, faíscas no metal, ricochete, acerto nos bonecos e nos objetos; marcador de acerto na mira
- **Socos** (animações prontas): jab → direto alternando; segurar = **gancho** forte; congelamento rápido no acerto, tranco da câmera, partículas e som por material
- **Interação com o cenário**: ao abrir/fechar uma porta a mão vai até a maçaneta (IK); para pegar munição ele se abaixa e a mão vai até a caixa
- **Lanterna** (`L`) presa na alça do ombro esquerdo, iluminando para onde se olha
- **Sons gravados de verdade** (CC0): passos por piso, impactos, portas rangendo, couro do coldre, tiro real (mais grave, com estrondo e eco sintetizados), carregador saindo/entrando, ferrolho, ambiente de pássaros e insetos — variação aleatória, som 3D
- **Texturas fotográficas** (Poly Haven, CC0), **céu HDRI**, **árvores** com cartões de folhas
- **Imagem nítida**: sem granulado; antisserrilhado MSAA numa passada final com **nitidez adaptativa** (tipo AMD CAS), filtragem anisotrópica 16x no chão
- **Bonecos de treino** de estopa: balançam conforme a força e direção do golpe e soltam palha

### Mundo pós-apocalíptico
- Carros abandonados enferrujados, queimados (só a carcaça), capotado, com pneus murchos, portas e capô abertos, vidros trincados
- Barricada na estrada com barril em chamas e placa de zona infectada
- Pichações ("SOCORRO", "ELES OUVEM", "NÃO ABRA – MORTOS DENTRO"...), marcas de mão de sangue, janelas fechadas com tábuas, musgo
- Lixo, papéis espalhados, buracos e mato crescendo na estrada, acampamento abandonado com barracas
- Colunas de fumaça de cidades queimando no horizonte; céu e luz mais sombrios
- Vilarejo (casa, cabana, posto, torre de vigia, contêineres), floresta de outono, lago com píer, portas que abrem, objetos com física

### Som
- Passos com síntese granular (folhas estalando, cascalho, madeira oca rangendo, metal), roupa e mochila balançando, respiração ofegante e gemidos de esforço
- Eco dentro das casas, som abafado debaixo d'água, fogo com som 3D, portas, impactos por material, faca saindo da bainha, soco

### Interface e plataformas
- HUD com vida, bússola, item na mão, mira dinâmica e dicas de contexto (escalar, escada, pendurado, porta, natação)
- Controles de PC, toque (Android) e controle; configurações de sensibilidade, FOV, volume, qualidade, antisserrilhado (liga/desliga), inverter Y, balanço da câmera, FPS, tamanho dos botões e vibração

## Controles

| Ação | PC | Android | Controle |
|---|---|---|---|
| Mover | `W A S D` / setas | Joystick (lado esquerdo) | Analógico esquerdo |
| Olhar | Mouse | Arrastar no lado direito | Analógico direito |
| Andar devagar | `X` (alterna) | Joystick pouco empurrado | `→` (direcional) |
| Correr | `Shift` | **CORRER** ou joystick no limite | `L3` (alterna) / `LT` |
| Mãos livres / faca / revólver / espingarda / besta / taco | `1` – `6` | Barra de armas no topo ou **TROCAR** | `←` (direcional) |
| Pular / escalar | `Espaço` | **PULAR** | `A` |
| Escada de mão | `W` / `S` (Espaço solta) | Joystick | Analógico |
| Agachar / deslizar (correndo) / rolar (caindo) | `C` (alterna) / `Ctrl` (segurar) | **AGACHAR** | `B` |
| Inclinar (espiar) | `Q` / `E` | — | `LB` / `RB` |
| Soco / golpe de faca / taco (combo) | Clique esquerdo | 👊 / 🔪 | `RT` |
| Golpe forte | Segurar e soltar o clique | Segurar 👊 / 🔪 | Segurar `RT` |
| Trocar item | Rodinha do mouse | **TROCAR** (próximo item) | `←` |
| Mirar / atirar / recarregar | Botão direito / clique / `R` | **MIRAR** / **ATIRAR** / **RECARR.** (arrastar sobre ATIRAR/MIRAR gira a câmera) | `LT` / `RT` / `↓` |
| Usar / porta | `F` | **USAR** (aparece perto da porta) | `X` |
| Lanterna | `L` | 🔦 | `↑` (direcional) |
| Nadar: mergulhar / subir | `Ctrl` / `Espaço` | **AGACHAR** / **PULAR** | `B` / `A` |
| 1ª / 3ª pessoa | `V` | 👁 | `Y` |
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
js/character.js     personagem: clipes de animação (pernas/tronco), olhar, IK dos braços e dedos, socos, interações
js/pistol.js        pistola: animações de FPS (rig invisível que guia os braços), Colt, sacar/guardar, mira, tiro, recarga
js/zombie.js        zumbi de teste andando de lá para cá
js/lens.js          passada final: lente de GoPro, nitidez adaptativa, tom e antisserrilhado
js/modelLoader.js   carrega os modelos 3D (.glb, ou glTF .json + geometria em texto no artifact)
js/world.js         mapa, céu, iluminação, relevo, vegetação e malha de colisão
js/effects.js       partículas: poeira, fumaça, brasas, folhas caindo, fogueira
js/flashlight.js    lanterna: modelo, luz que sai da lente, feixe e brilho
js/physics.js       objetos soltos com física (latas, garrafas, baldes...)
js/dummies.js       bonecos de treino (balanço com mola, marcas de corte e furos)
js/textures.js      texturas procedurais (canvas)
js/photoAssets.js   texturas fotográficas, material do terreno (mistura por altura) e céu HDRI
js/icons.js         ícones SVG dos botões touch
js/trees.js         copas de árvore com cartões de galhos/folhas (texturas desenhadas em canvas)
assets/             sons gravados (sfx/), texturas (tex/), céu HDRI (env/) e CREDITS.md
models/             personagem.glb (robô + animações), zumbi.glb, fps_pistola.glb (animações de FPS), colt.glb
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

- [“Cyberpunk Police bot [Animation ready]”](https://sketchfab.com/3d-models/cyberpunk-police-bot-animation-ready-b68e6cc1f2ce462bb0d34275adaa1110) por **everlasting17th** — CC BY 4.0 (personagem; sem as armas e o pedestal)
- [“Zombie Walk Test”](https://sketchfab.com/3d-models/zombie-walk-test-165fd9342c364216bfdd8c2f1102223c) por **OSCAR CREATIVO** — CC BY 4.0 (zumbi e a animação de andar dele)
- [“FPS pistol animations”](https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d) por **Cransh** — CC BY 4.0 (animações de FPS da pistola e o carregador)
- [“Colt M1911”](https://sketchfab.com/3d-models/colt-m1911-26adfd631730494ab0fc80c806eada77) por **Ole Gunnar Isager** — CC BY 4.0 (pistola)
- Animações do personagem: biblioteca do [Mesh2Motion](https://github.com/Mesh2Motion/mesh2motion-app) — CC0
