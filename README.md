# Sobrevivência 2×2 — laboratório de mecânicas (motor próprio, WebGL2 + APK Android)

Jogo 3D de sobrevivência em **primeira e terceira pessoa**, com **física realista**, mapa de **2 × 2 km** e **sem zumbis** (versão de testes).
Inspirado em **DayZ** (mundo aberto, inventário em grade, vegetação, clima) e **Project Zomboid** (estados de sobrevivência tipo *moodles*).
Roda no navegador (PC) e como **APK** (Android 7 → 16, otimizado para o POCO X7 Pro).

> O motor é próprio (`www/engine`), escrito em JavaScript/WebGL2, sem Three.js/Unity/Unreal. **Regra nº 1: nenhum modelo é criado do zero** — personagem, carros, machado, picareta, props e sons vêm da internet (CC0: Quaternius, Kenney, Poly Haven, OpenGameArt; ver `CREDITS.md`). Não há armas no jogo.

## Como jogar/testar

### No PC
```bash
node tools/serve.mjs 8080          # serve a pasta www/
# abra http://localhost:8080
```
Clique na tela para capturar o mouse. **Esc** abre o menu de testes (clima, hora, teleporte, spawn de itens, gráficos, desempenho).

### No celular (APK)
- Baixe o APK de [`dist/Sobrevivencia2x2-v1.1.apk`](dist/Sobrevivencia2x2-v1.1.apk) (ou o artefato do GitHub Actions) e instale (permita "fontes desconhecidas").
- Ou compile: veja *Compilar o APK* abaixo.

### Controles
Interface limpa: só aparece o que importa (nome do alvo, barras de estado quando estão baixas, atalhos preenchidos).

| Ação | PC | Celular |
|---|---|---|
| Mover / olhar | `WASD` / mouse | joystick à esquerda / arrastar à direita |
| Correr | `Shift` | empurrar o joystick até a borda |
| Agachar / pular | `C` / `Espaço` | botões à direita |
| **Interagir / usar ferramenta** | `F` ou clique esq. | **toque no objeto na tela** ou botão de ação |
| Cortar árvore / minerar pedra | equipar machado (`1`) / picareta (`2`) e clicar | toque na árvore/pedra |
| Entrar / sair do carro | `F` | toque no carro / botão de ação |
| Inventário | `Tab` ou `I` | ícone da mochila |
| Atalhos | `1`–`8` | barra no rodapé (só slots com item) |
| Câmera 1ª/3ª pessoa | `V` | ícone do olho |
| Lanterna / guardar | `L` / `H` | toque no atalho |
| Menu / depuração | `Esc` / `F3` | ícone de menu |

### O que testar
- **Machado e picareta** (modelos Poly Haven): derrube árvores (viram toras de madeira) e quebre pedras (viram pedra). Os itens vão para o inventário.
- **Carros** (Kenney): dirija com `WASD` (câmera de perseguição), com suspensão, derrapagem e som de motor/pneus.
- **Mundo:** 5 assentamentos, base militar a sudeste, lago, rio com ponte, floresta densa, montanhas, estradas, postes com fios.
- **Sobrevivência:** fome, sede, temperatura, sangue, estamina, umidade, perna quebrada, queda.
- **Itens:** menu → Itens; ou o kit espalhado perto do spawn.

## Estrutura
```
www/engine/    motor: renderer PBR+sombras, shaders, glTF, física, animação/IK, partículas, áudio, entrada
www/game/      jogo: mundo procedural, terreno, vegetação, construções, jogador, ferramentas, veículos, itens, UI
www/assets/    texturas, modelos, personagem e sons CC0 (tools/fetch_assets.py, build_character.py, import_external.py)
android/       projeto Gradle (WebView em tela cheia, 120 Hz, API 24–36)
tools/         servidor local, baixador de assets, scripts de captura de tela (Playwright)
docs/          pesquisa (DayZ, Project Zomboid, fontes de assets)
```
Detalhes técnicos em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) e a pesquisa em [`docs/PESQUISA.md`](docs/PESQUISA.md).

## Compilar o APK
Requisitos: JDK 17+, Android SDK (plataforma 36, build-tools 36.0.0).
```bash
export ANDROID_HOME=/caminho/do/sdk
cd android && ./gradlew assembleRelease
# saída: android/app/build/outputs/apk/release/app-release.apk
```
O APK é assinado com uma chave **de teste** (`android/app/test-release.jks`, senha `android`) apenas para sideload. Use a sua própria para publicar.
O GitHub Actions (`.github/workflows/android.yml`) compila o APK a cada push.

## Regenerar assets e mundo
```bash
python3 tools/fetch_assets.py          # baixa do Poly Haven e otimiza texturas/modelos
cd tools && npm install && cd ..       # (uma vez) meshoptimizer + gltf-transform
node tools/optimize_models.mjs         # simplifica a geometria pesada (rochas, hidrante, poste...)
node tools/bake_world.mjs              # gera o mapa 2x2 km e grava www/assets/world/ (embarcado no APK)
```
Sem os arquivos de `www/assets/world/` o jogo gera o mapa na hora (mais lento; use `?gen` para forçar).

## Assets de terceiros (scripts)
- `tools/build_character.py` — monta o personagem (Quaternius CC0) e suas 27 animações.
- `tools/import_external.py` — importa os carros (Kenney) e os sons (Kenney/OpenGameArt).

## Regenerar os assets (somente baixar)
```bash
pip install pillow
python3 tools/fetch_assets.py          # baixa do Poly Haven e otimiza (≈35 MB)
```

## Requisitos no Android
Android 7.0+ (API 24) com **Android System WebView / Chrome atualizado** (recomendado ≥ 90; o jogo usa módulos ES, WebGL2 e `?.`/`??`). O WebView é atualizado pela Play Store, inclusive no Android 7.

## Desempenho (alvo: POCO X7 Pro, 60 fps)
Predefinição **Alta**: 72% de resolução, 2 cascatas de sombra 2048, grama média. A **resolução dinâmica** reduz a escala se o quadro passar de ~18,5 ms e a recupera depois. Ajustes em Menu → Gráficos (resolução, sombras, grama, distância da vegetação, alcance, limite de 60 FPS) e números em Menu → Desempenho (draw calls, triângulos, árvores, GPU).

## Limitações conhecidas (v1.1)
- **Não foi possível rodar o APK em um aparelho/emulador neste ambiente**: tudo foi validado no Chromium (WebGL2 por software, mesmo código do APK). O **chão branco** relatado foi endurecido (texturas opacas, guardas contra NaN, fallback de cor), mas **precisa ser confirmado no aparelho**. O mesmo vale para o som no celular (desbloqueio do áudio no primeiro toque) e para o desempenho real.
- Sem zumbis, sem armas, sem multijogador, sem construção de base (ver roteiro em `docs/PESQUISA.md`).
- A geração do mundo leva alguns segundos na abertura (mais em celulares).
