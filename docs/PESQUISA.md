# Pesquisa: Project Zomboid, DayZ e fontes de assets

Resumo do que foi estudado para definir o escopo do laboratório, o que foi **adotado**, o que foi **adiado** e de onde vêm os assets.
Onde as fontes eram ruidosas ou contraditórias, isso está dito explicitamente.

## 1. DayZ (Standalone, motor Enfusion)

| Pilar | O que o jogo faz | No laboratório |
|---|---|---|
| Mundo | Chernarus: ~225 km² segundo vários sites de fãs (valores de 225 a 230 km² aparecem; um post antigo do Steam sugere só parte jogável). Floresta de coníferas e folhosas outonais, vilas de casas de madeira/concreto, estradas de asfalto, linhas de energia, torres d'água. | Mapa procedural de **2 × 2 km** (4 km²) com 5 assentamentos, rodovias, rio, lago, ponte, base militar, floresta com ~25 mil árvores, linhas de energia, carros abandonados. |
| Estados do personagem | Saúde, **sangue** (a escala 0–5000 aparece no jogo; wikis do mod antigo citam outras), choque (oculto), energia (fome), hidratação, **temperatura corporal**, umidade das roupas, estamina, peso. Sangue regenera quando fome e sede estão satisfeitas (uma fonte cita ~0,9 ml/s). Sangramento exige bandagem. | Implementado: saúde, sangue, comida (kcal), água (ml), temperatura corporal (ar + roupa + vento + chuva + molhado), umidade, estamina, sangramento, perna quebrada, queda com dano. Taxas aceleráveis (×1 a ×120) para testar. |
| Inventário | Boneco com slots (cabeça, rosto, torso, colete, pernas, pés, costas, mãos) + **grades por roupa/mochila**, atalhos 1–8, itens no chão ("vizinhança"). | Implementado em 3 colunas (Chão · Jogador · Mochilas) com arrastar e soltar, empilhar, dividir, atalhos e ícones renderizados dos próprios modelos 3D. |
| Armas | Balística real por projétil (velocidade, queda, arrasto), penetração, recuo, sway, respiração, ferrolho/semiauto, recarga por cartucho. | Projéteis integrados a 120 Hz+ com arrasto quadrático, gravidade e vento; zeragem a 100 m; penetração em madeira/metal fino; recuo de câmera e do modelo; segurar a respiração (Shift) na mira; ferrolho com ciclo e recarga cartucho a cartucho; pistola com carregador. |
| Veículos | Física de veículo com suspensão e atrito. | Raycast vehicle próprio: 4 molas/amortecedores, atrito lateral/longitudinal por pneu, freio de mão, combustível, faróis. |
| Ambiente | Ciclo dia/noite, clima, névoa, chuva, sons. | Céu procedural (sol, lua, estrelas, nuvens), 6 climas, névoa por altura, chuva, vento que afeta a vegetação e as balas, áudio 100% procedural. |
| Construção de base | Bases de madeira (torres de vigia, cercas). | **Adiado** (v2). As cercas e a torre/caixa d'água existem só como cenário. |
| Zumbis, multijogador, doenças | Núcleo do jogo. | **Fora do escopo desta versão (pedido: sem zumbis).** |

Referências consultadas (qualidade variável; vários resultados descrevem o mod de 2012, não o Standalone):
[DayZ wiki.gg – Beginners Guide](https://dayz.wiki.gg/wiki/Mod:A_Beginners_Guide), [wiki.gg – Hunger](https://dayz.wiki.gg/wiki/Hunger), [wiki.gg – Stomach](https://dayz.wiki.gg/wiki/Stomach), [Chernarus Map Guide](https://xgamingserver.com/blog/dayz-chernarus-map-guide/), [guia de regeneração de sangue/saúde](https://wobo.tools/guides/how-blood-and-health-regeneration-works-in-dayz-temperature-hunger-and-thirst-stats-explained/).
Os números exatos de taxas do Standalone **não** foram confirmados por fonte oficial; os valores do laboratório são calibrados para teste, não cópias.

## 2. Project Zomboid

| Pilar | O que o jogo faz | No laboratório |
|---|---|---|
| Moodles | Ícones de estado (fome, sede, cansaço, dor, doença, temperatura, umidade, pânico…); o Build 42 tem em torno de duas dezenas e meia, com 4 níveis. (As contagens variam entre sites: 23, 24 ou 26.) | Os estados principais viram **ícones circulares** no HUD que mudam de cor por nível (branco → amarelo → vermelho; azul para frio). |
| Habilidades/traços | Fitness, força, mira, carpintaria… sobem com o uso. | Adiado. |
| Nutrição e peso | Calorias, peso corporal, tipos de comida. | Calorias e peso transportado (afeta a velocidade). |
| Crafting/construção/agricultura/pesca | Muito profundos; Build 42 (instável em dez/2024; uma fonte afirma 42.20 estável em jul/2026 — **não confirmado**) refaz crafting, pesca e adiciona animais. | Adiado. |
| Ruído/visão | Zumbis reagem a som e visão. | Os sons do laboratório já têm atenuação por distância (preparação para IA futura). |

Referências: [projectzomboid.wiki – Moodles](https://projectzomboid.wiki/guides/moodles/), [pindrop.gg – Moodles](https://pindrop.gg/project-zomboid/moodles), [G-Portal – Build 42](https://www.g-portal.com/en/news/project-zomboid-build-42-update-en), [Insider Gaming – Build 42](https://insider-gaming.com/whats-included-in-project-zomboid-build-42/).

## 3. Decisões técnicas (motor próprio)

- **Plataforma:** WebGL2 dentro de um `WebView` Android. É a forma mais rápida de ter um motor 3D próprio, testável em PC e idêntico no celular, compatível do Android 7 ao 16 (o WebView é atualizado pela Play Store). Um motor nativo em C++/NDK daria mais controle, mas multiplicaria o tempo de desenvolvimento e impediria testar aqui. O desempenho de WebGL2 em GPU Mali moderna (POCO X7 Pro = Dimensity 8400-Ultra / Mali-G720) é adequado para este escopo.
- **Terreno:** heightmap `R32F` 1001² (2 m) amostrado no *vertex shader* (`texelFetch`); 256 chunks com 5 níveis de LOD e "saias"; materiais por *splat map* + `texture array`; normais pré-calculadas.
- **Vegetação:** árvores procedurais com 4 LODs (galhos recortados → versão simplificada → cones → silhuetas cruzadas), instanciadas por células de 64 m, vento no vertex shader; grama gerada inteiramente na GPU ao redor da câmera; cobertura de solo com modelos CC0.
- **Iluminação:** PBR (GGX), sombras em cascata (até 3, `sampler2DArrayShadow`), céu/nuvens/estrelas procedurais, névoa exponencial por altura, ACES, lanterna e faróis como *spot lights*.
- **Física:** colisão estática por grade espacial (OBB/cilindro) + heightfield; *character controller* de cápsula (degraus, inclinações, água); corpos rígidos 6-DOF com impulsos, atrito e restituição; balística; veículo.
- **Animação:** esqueleto glTF com FK, blend por velocidade, IK de 2 ossos nas pernas (pés no terreno) e braços (arma), torção/inclinação do tronco pela mira.
- **Otimização para celular:** *render scale* + **resolução dinâmica** (mira ~54 fps), MSAA do canvas, um único UBO de cena, instancing, culling por frustum em células, texturas JPEG/WebP redimensionadas (≤1024), sem pós-processamento em tela cheia, shaders compilados sob demanda.

## 4. Fontes de assets avaliadas

| Fonte | Licença | Acesso neste ambiente | Uso |
|---|---|---|---|
| [Poly Haven](https://polyhaven.com) (API `api.polyhaven.com`) | **CC0** | OK | **Usado**: texturas PBR, rifle Mosin, pistola, machadinha, facão, lanterna, comidas, galões, caixas, barris, pedras, samambaias, mobiliário urbano. |
| [ambientCG](https://ambientcg.com) | CC0 | OK | Alternativa para texturas (não necessário). |
| [Quaternius](https://quaternius.com) | CC0 | página OK (downloads em Google Drive) | Sugestão futura: personagens/armas low-poly. |
| [Kenney](https://kenney.nl) | CC0 | bloqueado (HTTP 403) | Não usado. |
| [OpenGameArt](https://opengameart.org) | variada | página OK | Exige conferir a licença item a item. |
| [Sketchfab](https://sketchfab.com) | variada, exige login | página OK | Não usado. |
| three.js `examples/models` (`Soldier.glb`) | modelo do Mixamo | OK | **Usado como personagem provisório** — veja `CREDITS.md` (restrições do Mixamo). |

Observação: as árvores do Poly Haven têm de 60 MB a 950 MB de geometria por modelo — inviáveis no celular. Por isso as árvores foram geradas proceduralmente pelo motor.

## 5. Roteiro sugerido (v2+)

1. Construção de base com encaixes (paredes, portas, torre de vigia) e baús.
2. Troca do personagem por um CC0 com animações de agachar/deitar/mirar e orientação correta das mãos.
3. Fogo/acampamento, cozinhar, caça e pesca.
4. Zumbis (IA de visão/audição) e multijogador.
5. Compressão de texturas (KTX2/Basis) e *impostors* de árvores para mais distância de visão.
