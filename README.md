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
- Ciclo de passo realista (andar, trotar, correr, agachado): joelhos, tornozelos, quadril subindo/descendo e girando, ombros em contrarrotação, braços com cotovelo, inclinação com a velocidade
- **IK de braço**: as mãos se apoiam de verdade na borda ao escalar e nos degraus da escada
- Parado muda o peso de perna, dá passinhos ao girar; inclina nas curvas; amortece pousos
- 3ª pessoa (`V`) com colisão da câmera

### Itens e combate
- **Mãos livres** ou **faca** (`1` / `2`): a faca fica guardada na bainha no quadril e é sacada com animação e som
- **Soco** com as mãos livres e **golpe de faca** (acertam objetos, portas e paredes)
- **Lanterna** (`L`): presa no peito quando desligada; ligada, vai para a mão esquerda e a luz sai da lente

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
- Controles de PC, toque (Android) e controle; configurações de sensibilidade, FOV, volume, qualidade, inverter Y, balanço da câmera, FPS, tamanho dos botões e vibração

## Controles

| Ação | PC | Android | Controle |
|---|---|---|---|
| Mover | `W A S D` / setas | Joystick (lado esquerdo) | Analógico esquerdo |
| Olhar | Mouse | Arrastar no lado direito | Analógico direito |
| Andar devagar | `X` (alterna) | Joystick pouco empurrado | `→` (direcional) |
| Correr | `Shift` | **CORRER** ou joystick no limite | `L3` (alterna) / `LT` |
| Mãos livres / faca | `1` / `2` | **✊⇄🔪** | `←` (direcional) |
| Pular / escalar | `Espaço` | **PULAR** | `A` |
| Escada de mão | `W` / `S` (Espaço solta) | Joystick | Analógico |
| Agachar / deslizar (correndo) / rolar (caindo) | `C` (alterna) / `Ctrl` (segurar) | **AGACHAR** | `B` |
| Inclinar (espiar) | `Q` / `E` | — | `LB` / `RB` |
| Soco / golpe de faca | Clique esquerdo | 👊 / 🔪 | `RT` |
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
js/textures.js      texturas procedurais (canvas)
js/audio.js         sons procedurais (Web Audio)
```

No console do navegador, `window.game` dá acesso ao jogador e ao mundo para depuração.

## Próximas etapas (sugestão)

2. Inventário e itens no chão (coletar)
3. Fome, sede e temperatura
4. Zumbis com IA (patrulha, perseguição, ataque)
5. Combate corpo a corpo / armas
6. Construção e coleta de recursos (estilo Minecraft)
7. Ciclo dia/noite e salvamento
