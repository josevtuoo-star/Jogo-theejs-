# Sobrevivência 2×2 — laboratório de mecânicas (motor próprio, WebGL2 + APK Android)

Jogo 3D de sobrevivência em **primeira e terceira pessoa**, com **física realista**, mapa de **2 × 2 km** e **sem zumbis** (versão de testes).
Inspirado em **DayZ** (mundo aberto, inventário em grade, balística, vegetação, clima) e **Project Zomboid** (estados de sobrevivência tipo *moodles*).
Roda no navegador (PC) e como **APK** (Android 7 → 16, otimizado para o POCO X7 Pro).

> O motor é próprio (`www/engine`), escrito em JavaScript/WebGL2, sem Three.js/Unity/Unreal. Os modelos e texturas são CC0 do Poly Haven (ver `CREDITS.md`).

## Como jogar/testar

### No PC
```bash
node tools/serve.mjs 8080          # serve a pasta www/
# abra http://localhost:8080
```
Clique na tela para capturar o mouse. **Esc** abre o menu de testes (clima, hora, teleporte, spawn de itens, gráficos, desempenho).

### No celular (APK)
- Baixe o APK de [`dist/Sobrevivencia2x2-v1.0.apk`](dist/Sobrevivencia2x2-v1.0.apk) (ou o artefato do GitHub Actions) e instale (permita "fontes desconhecidas").
- Ou compile: veja *Compilar o APK* abaixo.

### Controles
| Ação | PC | Celular |
|---|---|---|
| Mover / olhar | `WASD` / mouse | joystick à esquerda / arrastar à direita |
| Correr | `Shift` | `»` ou empurrar o joystick |
| Agachar / deitar | `C` / `Z` | `⤓` / `▭` |
| Pular | `Espaço` | `⤒` |
| Atirar / mirar | botão esq. / dir. (`Shift` segura a respiração) | `🔥` / `🎯` |
| Recarregar | `R` | `⟳` |
| Interagir / pegar | `F` | botão `F` (aparece perto de itens/carros) |
| Inventário | `Tab` ou `I` | `🎒` |
| Atalhos de itens | `1`–`8` | barra no rodapé |
| Câmera 1ª/3ª pessoa | `V` | `👁` |
| Lanterna / guardar item | `L` / `H` | `🔦` / `✋` |
| Inclinar | `Q` / `E` | — |
| Voar (teste) / criar carro | `N` / `K` | menu → Jogador |
| Menu / depuração | `Esc` / `F3` | `☰` |

### O que testar (cada item tem um lugar no mapa)
- **Polígono de testes** (você nasce ao lado): alvos a 25, 50, 100, 150, 200 e 300 m (queda e velocidade reais do projétil), pilha de caixas, barris e pneus (corpos rígidos), degraus, paredes de madeira/concreto/metal (penetração), 2 carros.
- **Mundo:** 5 assentamentos (Vila Nova, Porto do Lago, Serra Alta, Campo Seco, Posto Norte), base militar a sudeste, lago, rio com ponte, floresta densa, montanhas, estradas, postes com fios.
- **Sobrevivência:** fome, sede, temperatura, sangue, estamina, umidade, perna quebrada, queda. Velocidade das taxas em Menu → Jogo.
- **Itens:** menu → Itens; ou o kit espalhado em círculo perto do spawn.

## Estrutura
```
www/engine/    motor: renderer PBR+sombras, shaders, glTF, física, animação/IK, partículas, áudio, entrada
www/game/      jogo: mundo procedural, terreno, vegetação, construções, jogador, armas, itens, UI
www/assets/    texturas e modelos otimizados (gerados por tools/fetch_assets.py)
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

## Regenerar os assets (somente baixar)
```bash
pip install pillow
python3 tools/fetch_assets.py          # baixa do Poly Haven e otimiza (≈35 MB)
```

## Requisitos no Android
Android 7.0+ (API 24) com **Android System WebView / Chrome atualizado** (recomendado ≥ 90; o jogo usa módulos ES, WebGL2 e `?.`/`??`). O WebView é atualizado pela Play Store, inclusive no Android 7.

## Desempenho (alvo: POCO X7 Pro, 60 fps)
Predefinição **Alta**: 72% de resolução, 2 cascatas de sombra 2048, grama média. A **resolução dinâmica** reduz a escala se o quadro passar de ~18,5 ms e a recupera depois. Ajustes em Menu → Gráficos (resolução, sombras, grama, distância da vegetação, alcance, limite de 60 FPS) e números em Menu → Desempenho (draw calls, triângulos, árvores, GPU).

## Limitações conhecidas da v1
- **Não foi possível rodar o APK em um aparelho/emulador neste ambiente**: o jogo foi validado no Chromium (WebGL2 por software, mesmo código servido pelo APK) e o APK foi compilado e verificado (assinatura, manifesto, conteúdo). O desempenho real no celular precisa ser medido por você.
- O personagem é um placeholder (Mixamo "Vanguard"); a orientação das mãos na arma e as poses de agachar/deitar são procedurais e simples.
- Sem zumbis, sem multijogador, sem construção de base (ver roteiro em `docs/PESQUISA.md`).
- A geração do mundo leva alguns segundos na abertura (mais em celulares).
