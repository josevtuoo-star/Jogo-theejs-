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
- **1ª pessoa de verdade**: a câmera fica nos olhos do próprio corpo. Braços, mãos, faca e lanterna que aparecem em 1ª pessoa são os mesmos da 3ª pessoa, fazendo o mesmo movimento
- **Captura de movimento real** (CMU Graphics Lab Motion Capture Database): andar, trotar, correr e andar agachado vêm de gravações de pessoas de verdade, adaptadas ao esqueleto do personagem (quadril, tronco, coxas, joelhos, tornozelos e braços) e tocadas no ritmo do passo do jogo — o som da pisada cai na pisada; os clipes se misturam pela velocidade
- Ciclo de passo procedural por baixo (de lado, de costas, transições): joelhos, tornozelos, quadril subindo/descendo e girando, ombros em contrarrotação, braços com cotovelo, inclinação com a velocidade
- **IK de braço e perna**: as mãos se apoiam de verdade na borda ao escalar e nos degraus da escada; na escada os pés também pisam nos degraus, alternando com as mãos
- Parado muda o peso de perna, dá passinhos ao girar; inclina nas curvas; amortece pousos
- 3ª pessoa (`V`) com colisão da câmera

### Itens e combate
- **Personagem realista com esqueleto próprio** (`models/sobrevivente.glb`, CC0): jaqueta de couro e jeans, malha suavizada, pesos de pele de verdade (ombro, cotovelo e dedos deformam certo). O esqueleto do jogo (captura de movimento + IK) dirige os ossos do modelo a cada quadro: coluna em três vértebras, pescoço, clavículas que sobem/avançam com o braço e dedos que fecham na pegada; em 1ª pessoa só a cabeça some (você vê seu próprio corpo e as mangas da jaqueta)
- **Interação com o cenário**: ao abrir/fechar uma porta a mão vai até a maçaneta, gira (trinco) e acompanha a porta empurrando; para pegar munição/virotes ele se abaixa e a mão vai até o objeto
- **Mãos livres** ou **faca** (`1` / `2`): a faca fica guardada na bainha no quadril e é sacada com animação e som
- **Combos**: mãos livres = jab → direto → gancho; faca = corte → corte de volta → estocada
- **Golpe forte**: segurar o botão carrega (o braço vai para trás) e soltar desfere — soco giratório ou facada de cima para baixo, com passo à frente
- Guarda alta com os punhos durante a briga, punho fechado segurando a faca
- Impacto com peso: congelamento rápido no acerto, tranco da câmera, vibração, partículas e som por material
- **6 itens** (`1`–`6`, rodinha, botão **TROCAR** ou a **barra de armas** na tela): mãos livres, faca, revólver, espingarda, besta e taco
- **Espingarda de cano duplo calibre 12** (`4`), pendurada nas costas: nove bagos de chumbo num cone por tiro, dois canos (dois tiros seguidos), recuo forte, clarão e fumaça; **recarga animada**: abre a báscula (os canos caem), os cartuchos vazios saltam e quicam no chão, a mão esquerda pega dois cartuchos no cinto, põe nas câmaras e fecha com um tranco
- **Besta** (`5`), pendurada nas costas: mira de ponto vermelho, **virote que voa com gravidade** (é preciso compensar a queda de longe), crava em madeira, terra e nos bonecos (fica preso e treme), ricocheteia em metal/concreto — e **dá para recolher** os virotes (`F`); recarga: aponta para baixo, puxa a corda até o trinco e põe o virote no trilho
- **Taco com arame farpado** (`6`), preso no cinto: golpes com as duas mãos no cabo — arco horizontal → golpe de volta → estocada com a ponta; segurando, **golpe forte de cima para baixo**; o arame rasga a lona dos bonecos, pancada que volta pelo cabo nas paredes
- Armas longas se sacam por cima do ombro (a mão vai às costas, puxa e traz para frente); com a lanterna ligada, ela fica presa no peito iluminando (as duas mãos estão na arma)
- Munição separada por arma, caixas de **.357**, **cartuchos cal. 12** e **feixes de virotes** espalhadas pelo mapa
- **Revólver .357** (`3`), guardado no coldre da coxa: sacar/guardar animado, arma baixa e pronta, **mirar pela alça e massa** (`botão direito` / **MIRAR** / `LT`) com zoom, recuo com o cano subindo, tambor que gira a cada tiro, cão que arma, clarão e fumaça
- **Sacar e guardar animados** (revólver e faca): a mão vai até o coldre/bainha, segura, puxa para cima, gira e traz para frente; guardar faz o caminho inverso
- Mãos de verdade na arma: a direita envolve a empunhadura com o polegar por cima, a esquerda apoia por baixo
- **Lanterna com o revólver**: uma mão na arma e a outra segurando a lanterna ao lado, iluminando para onde se mira — atirando com uma mão só a arma balança mais, o recuo é maior e a precisão cai bastante
- **Sons gravados de verdade** (CC0): passos por piso (grama com folhas secas, concreto, madeira), impactos de soco, metal, madeira, vidro e lata, portas rangendo, faca saindo da bainha, couro do coldre, roupa, tiro real (mais grave, com estrondo e eco sintetizados), recarga, ambiente de pássaros e insetos — variação aleatória sem repetir, tom e volume levemente diferentes a cada vez, som 3D
- **Texturas fotográficas** (Poly Haven, CC0): terreno misturando grama, chão seco de outono com folhas e gravetos e rocha com musgo (mistura por altura, duas escalas para não repetir), terra escura nas trilhas, asfalto com pedriscos, tijolo real com relevo, tábuas velhas
- **Iluminação de céu real** (HDRI do Poly Haven) ajustada para um dia nublado de outono
- **Árvores de verdade**: pinheiros com verticilos de galhos de agulhas caindo com o peso e árvores de outono com cachos de folhas (cartões recortados em volta de um miolo escuro, normais "infladas" e sombra com os furos entre as folhas); arbustos idem
- Clima de cinema: vinheta suave e granulado de filme leve
- Câmera em 3ª pessoa sobe e se afasta do muro quando o personagem está pendurado/escalando
- Passos sintetizados amostra a amostra por piso (grama/terra, concreto, madeira, metal), 6 variações cada, pé esquerdo/direito
- Controles do celular refeitos: ícones desenhados (iguais em qualquer aparelho), layout de jogo de tiro, munição embaixo da vida
- Som do tiro sintetizado amostra a amostra (estalo, explosão, pancada grave, cauda) com eco do vale; compressor no áudio para não estourar
- **Recarga animada** (`R` / 🔄 / `↓`): abre o tambor, ejeta as cápsulas (que caem e tilintam no chão), pega o speedloader no cinto, carrega e fecha
- Munição limitada (6 no tambor + reserva); **caixas de munição .357** espalhadas pelo mapa (`F` para pegar)
- Bala com dispersão (precisa mirar para acertar longe), furos nas superfícies, faíscas no metal, ricochete, acerto nos bonecos e nos objetos (latas voam); marcador de acerto na mira
- Mirando, o personagem anda devagar e não corre; em 3ª pessoa a câmera aproxima
- **Andar de lado/diagonal** com o quadril e as pernas virando para a direção do passo e o tronco mirando para frente
- **Bonecos de treino** de estopa: balançam conforme a força e direção do golpe, guardam as marcas de corte e soltam palha
- **Lanterna** (`L`): presa no peito quando desligada; ligada, vai para a mão esquerda e a luz sai da lente (corpo serrilhado, clipe de bolso, refletor cromado e vidro)

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
js/cameraRig.js     efeitos de câmera e câmera em 3ª pessoa
js/character.js     corpo do personagem (1ª e 3ª pessoa): animação procedural, IK de braço, itens
js/world.js         mapa, céu, iluminação, relevo, vegetação e malha de colisão
js/effects.js       partículas: poeira, fumaça, brasas, folhas caindo, fogueira
js/flashlight.js    lanterna: modelo, luz que sai da lente, feixe e brilho
js/physics.js       objetos soltos com física (latas, garrafas, baldes...)
js/playerModel.js   carrega os modelos 3D (personagem com pesos automáticos no esqueleto, faca)
js/dummies.js       bonecos de treino (balanço com mola, marcas de corte e furos)
js/revolver.js      revólver: modelo, tambor, cão, clarão, cápsulas
js/weapons.js       espingarda de cano duplo, besta (corda, virote) e taco com arame farpado
js/mocap.js         clipes de captura de movimento (andar, trotar, correr, agachado) e mistura
js/textures.js      texturas procedurais (canvas)
js/photoAssets.js   texturas fotográficas, material do terreno (mistura por altura) e céu HDRI
js/icons.js         ícones SVG dos botões touch
js/trees.js         copas de árvore com cartões de galhos/folhas (texturas desenhadas em canvas)
assets/             sons gravados (sfx/), texturas (tex/), céu HDRI (env/), animações de captura de movimento (anim/) e CREDITS.md
models/             sobrevivente.glb (personagem com esqueleto) e faca.glb
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
Poly Haven (CC0) e captura de movimento da CMU Graphics Lab Motion Capture Database
(mocap.cs.cmu.edu). Lista completa, com links e o que foi alterado em cada arquivo:
[`assets/CREDITS.md`](assets/CREDITS.md).

## Créditos dos modelos 3D

- Personagem “Male 15” por **elbolilloduro**, do projeto [Mesh2Motion](https://github.com/Mesh2Motion/mesh2motion-app) (esqueleto humano do Mesh2Motion) — CC0. No jogo a malha foi suavizada (subdivisão com triângulos curvos, 920 → 14.720 triângulos) mantendo textura e pesos de pele.
- “Faca de Ação” por **Wesley Pontes** — https://sketchfab.com/3d-models/faca-de-acao-07d233fb3a124bf8baf276e2f0fb730b — licença CC BY 4.0.
