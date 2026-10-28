# Jogo-theejs- — Sobrevivência (Three.js)

Jogo de sobrevivência em primeira pessoa (estilo DayZ / Minecraft / The Walking Dead) feito com **Three.js**, rodando direto no navegador em **PC e Android**. Não precisa instalar nada nem compilar: o Three.js é carregado por CDN.

## Etapa 1 — Personagem jogável ✅

- **Movimento** com aceleração/desaceleração suave, andar de costas mais lento
- **Câmera em primeira pessoa** (mouse com pointer lock / arrastar no celular) e **terceira pessoa** (tecla `V`) com colisão contra paredes
- **Corrida** com barra de **fôlego** (esgota e precisa recuperar)
- **Pulo** com *coyote time* e *buffer* de pulo; **pulo agachado** alcança mais alto
- **Agachar** (não deixa levantar se tiver teto em cima)
- **Colisões** com chão, paredes, rampas, escadas, teto, carros, contêineres, árvores, cerca e limites do mapa (cápsula + Octree)
- **Dano de queda** e renascimento ao morrer/cair do mapa
- **Animações procedurais**: balanço da cabeça, inclinação lateral, tranco ao pousar, FOV maior correndo, braços em 1ª pessoa (respiração, passo, corrida, balanço ao olhar, golpe de faca) e corpo completo em 3ª pessoa (parado, andar, correr, agachar, pular, atacar)
- **Sons procedurais** (passos, pulo, pouso, golpe, vento) — sem arquivos de áudio
- **Lanterna** (`F`)
- Mapa: vilarejo abandonado com casa de tijolos (porta, janelas, terraço com escada), contêineres com rampa, carros, caixotes, barris, cerca e floresta com relevo

## Controles

| Ação | PC | Android |
|---|---|---|
| Mover | `W A S D` / setas | Joystick (lado esquerdo da tela) |
| Olhar | Mouse | Arrastar no lado direito da tela |
| Correr | `Shift` | Botão **CORRER** ou joystick empurrado até o limite |
| Pular | `Espaço` | Botão **PULAR** |
| Agachar | `C` (alterna) / `Ctrl` (segurar) | Botão **AGACHAR** |
| Atacar | Clique esquerdo | Botão 🔪 |
| Lanterna | `F` | Botão 🔦 |
| 1ª / 3ª pessoa | `V` | Botão 👁 |
| Pausar | `Esc` | Botão ❚❚ |

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
js/player.js        física do personagem (cápsula, gravidade, pulo, agachar, fôlego, dano)
js/cameraRig.js     efeitos de câmera e câmera em 3ª pessoa
js/viewmodel.js     braços e faca em 1ª pessoa (animações)
js/character.js     corpo do personagem em 3ª pessoa (animações)
js/world.js         mapa, iluminação, relevo e malha de colisão
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
