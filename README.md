# Jogo-theejs- — Sobrevivência (Three.js)

Jogo de sobrevivência em primeira pessoa (estilo DayZ / Minecraft / The Walking Dead) feito com **Three.js**, rodando direto no navegador em **PC e Android**. Não precisa instalar nada nem compilar: o Three.js é carregado por CDN.

## Etapa 1 — Personagem jogável ✅

### Movimento
- Andar, **correr sem limite** (não há barra de fôlego), pular com *coyote time* e *buffer*, agachar
- **Deslizar**: agachar enquanto corre
- **Rolamento**: agachar logo antes de cair no chão reduz bastante o dano da queda
- **Escalar e pular obstáculos** (estilo DayZ): caixotes, barris, muros, janelas; cercas baixas são puladas por cima
- **Escadas de mão**: na torre de vigia e nos contêineres (subir, descer pelo topo, soltar pulando)
- **Inclinar/espiar** com `Q`/`E` sem atravessar paredes
- **Degraus baixos** (troncos, varandas, meio-fio) são subidos sem pular
- **Água**: andar na parte rasa (mais lento), **nadar**, **mergulhar** e subir no píer pela água; cair na água amortece a queda
- Colisões com cápsula + Octree (chão, paredes, rampas, escadas, teto, portas), dano de queda, morte e renascimento

### Mecânicas
- **Lanterna de verdade**: o modelo fica na mão (1ª e 3ª pessoa), a luz sai da lente e aponta para a mira, com feixe visível, sombras, anel de refletor e mau contato de vez em quando
- **Portas** que abrem e fecham (`F` / **USAR**), abrindo para longe de quem empurra e parando se baterem no jogador
- **Objetos com física**: latas, garrafas, baldes, galões, panelas e caixinhas caem, rolam e são chutados ao passar; a faca também os arremessa
- **Faca** acerta paredes, chão, portas e objetos com som e partículas (faíscas no metal, lascas na madeira, poeira)

### Câmera e animações
- 1ª pessoa com balanço da cabeça, inclinação, tranco no pouso, FOV maior correndo/deslizando
- **Corpo visível em 1ª pessoa**: ao olhar para baixo você vê suas pernas, e sua sombra aparece no chão
- 3ª pessoa (`V`) com colisão da câmera
- Braços em 1ª pessoa e corpo completo (rosto, gorro, mochila, mãos, cotovelos e joelhos) com animações de parado (mudando o peso), girar no lugar, andar, correr (inclinando nas curvas), agachar, pular, pouso, escalar, escada, deslizar, rolar, nadar, segurar a lanterna, inclinar, atacar e morrer
- Os braços recolhem perto de paredes e inclinam ao andar de lado

### Mundo e gráficos
- Céu procedural com sol e nuvens em movimento; luz de fim de tarde e reflexos do ambiente
- Terreno com grama verde e seca, terra, trilhas e pedra nas encostas; estrada de asfalto atravessando o mapa
- Floresta de outono: pinheiros, árvores coloridas, árvores mortas, arbustos, pedras e troncos caídos; grama e copas balançando com o vento
- Vilarejo: casa de tijolos com terraço, cabana de madeira, posto de gasolina com loja, torre de vigia, contêineres, carros detalhados (faróis, bancos, volante, calotas; um capotado), sacos de areia, fogueira acesa
- Lago na floresta com píer, juncos e vitórias-régias; visão e som abafados debaixo d'água
- Efeitos: poeira ao pousar/deslizar/correr, fumaça e brasas da fogueira, folhas caindo
- Objetos estáticos agrupados por material e região (poucos draw calls) e grama em blocos que somem com a distância

### Som
- Passos diferentes em grama, concreto, madeira e metal; escada, deslize, rolamento, escalada, dor
- Ambiente: vento (abafado dentro de casa), pássaros e corvos ao longe, fogueira com som 3D vindo da direção dela
- Eco dentro das casas, som abafado debaixo d'água, bolhas, respingos e braçadas
- Portas rangendo e batendo, impactos diferentes para lata, vidro, metal, madeira; batimento cardíaco com pouca vida

### Interface e plataformas
- HUD com vida, bússola, mira que abre com o movimento, dicas de escalar/escada, vinheta de ferimento
- Controles de PC, toque (Android, com vibração e tamanho dos botões ajustável) e controle (gamepad)
- Configurações: sensibilidade, campo de visão, volume, qualidade (automática ajusta a resolução pelo FPS), inverter Y, balanço da câmera, FPS

## Controles

| Ação | PC | Android | Controle |
|---|---|---|---|
| Mover | `W A S D` / setas | Joystick (lado esquerdo) | Analógico esquerdo |
| Olhar | Mouse | Arrastar no lado direito | Analógico direito |
| Correr | `Shift` | **CORRER** ou joystick no limite | `L3` (alterna) / `LT` |
| Pular / escalar | `Espaço` | **PULAR** | `A` |
| Escada de mão | `W` / `S` (Espaço solta) | Joystick | Analógico |
| Agachar / deslizar (correndo) / rolar (caindo) | `C` (alterna) / `Ctrl` (segurar) | **AGACHAR** | `B` |
| Inclinar (espiar) | `Q` / `E` | — | `LB` / `RB` |
| Atacar | Clique esquerdo | 🔪 | `RT` |
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
js/viewmodel.js     braços e faca em 1ª pessoa (animações)
js/character.js     corpo do personagem em 3ª pessoa (animações)
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
