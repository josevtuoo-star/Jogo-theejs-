# Etapa 4 — Reconstrução visual, corpo completo e câmera 1ª/3ª pessoa

Referência: DayZ. Objetivo: trocar tudo o que era provisório (braços procedurais, chão quadriculado, objetos de primitivas, painel de depuração na tela) por um personagem humano de verdade, um cenário com materiais PBR e uma câmera em primeira e terceira pessoa com transição suave, sem perder nada do que já funcionava (física das etapas 1 e 2, vida, combate, interação e morte da etapa 3).

## 1. Diagnóstico do projeto (antes da reconstrução)

| Área | Situação encontrada | Problema |
|---|---|---|
| Personagem | Só **braços flutuantes** (19 ossos, malha procedural de cilindros), presos à câmera | Não existe corpo: sem pernas ao olhar para baixo, sem sombra, impossível ter terceira pessoa ou ragdoll |
| Animações | 19 animações autorais "feitas à mão" por código | Movimento rígido e genérico; nenhuma é captura de movimento |
| Câmera | Só primeira pessoa, câmera dentro da `Head` | Nenhum suporte a terceira pessoa, órbita ou colisão de câmera |
| Morte | Câmera presa a um corpo rígido em forma de cápsula | Não há corpo para cair; o "ragdoll" era só a câmera |
| Cenário | Ginásio de calibração: chão com shader de grade, caixas e rampas de primitivas | Feito para testar física, não para jogar; nenhum material realista |
| Iluminação | Céu padrão, sem neblina, sombras básicas | Visual "de editor" |
| Interface | Painel de depuração (FPS, velocidade, estado) sempre visível; barras simples | Aparência de protótipo |
| Texturas | Importadas **sem mipmaps e sem compressão de vídeo** | Cintilação à distância e uso alto de memória no celular |
| Arquitetura | Animador (`FirstPersonAnimator`) e "viewmodel" acoplados à câmera | Toda a cadeia de animação dependia da primeira pessoa |

O que estava **bom e foi preservado**: o controlador físico (CharacterBody3D com Jolt, passada física, inércia, superfícies, quedas, degraus), vida/lesões, combate por evento de quadro, interação por contato da mão, controles de toque multitoque e as duas baterias de testes.

## 2. Plano de reconstrução

1. **Assets com licença verificada:** personagem humano e animações de captura CC0, materiais e objetos PBR CC0. Nada de Mixamo (o repositório é público e os termos proíbem redistribuir os arquivos).
2. **Corpo único:** um só personagem animado serve às duas câmeras. Em primeira pessoa a câmera fica nos olhos dele e a cabeça é escondida (só ela); braços, tronco, pernas e sombra são os mesmos da terceira pessoa.
3. **Animador do corpo inteiro** dirigido pela física (fase da passada, altura da cápsula, velocidade vertical, vida), com camadas só do peito para cima para golpes, ferimentos e interação.
4. **Câmera 1ª/3ª pessoa** independente do corpo, com transição contínua e colisão.
5. **Ragdoll de verdade** na morte, com o impulso do golpe.
6. **Cenário de demonstração** com terreno PBR, floresta, posto militar abandonado, fogueira, neblina e sombras.
7. **HUD limpo** e botão de câmera no toque; painel de depuração escondido (F3).
8. **Testes** de tudo, incluindo os 8 cenários obrigatórios da câmera, nas versões 4.5.1 e 4.7.1 do Godot.

## 3. O que foi implementado

### 3.1 Personagem (`scenes/characters/survivor.tscn`)

- **Base:** Quaternius *Universal Base Characters* (CC0): homem adulto, esqueleto de 65 ossos padrão UE, cerca de 14 mil triângulos, texturas PBR (cor, normal, rugosidade), olhos, cabelo raspado, barba e sobrancelhas.
- **Roupas geradas** por `tools/build_survivor.gd` a partir da própria malha do corpo, com os mesmos pesos de osso. Assim elas deformam junto, sem atravessar a pele:
  - a geometria é classificada por osso e deslocada ao longo da normal;
  - a borda é suavizada e as faces do corpo cobertas são removidas;
  - **jaqueta** de algodão verde-oliva, **calça** jeans e **botas** de couro, com texturas PBR da Poly Haven.
- **Malhas de primeira pessoa:** `BodyFirstPerson` e `JacketFirstPerson` são o corpo e a jaqueta sem cabeça e pescoço.
  - Em primeira pessoa ficam visíveis; as malhas completas passam a "só sombra".
  - Assim a sombra no chão é inteira, a câmera não vê o interior da cabeça e não há braços duplicados.
- **Ragdoll:** `PhysicalBoneSimulator3D` com 16 ossos físicos:
  - corpos em cápsula com o comprimento real de cada osso e juntas em cone com limites anatômicos;
  - cerca de 79 kg no total;
  - camada 8 ("ragdoll"), que colide com o mundo e os objetos.

### 3.2 Animações (`tools/retarget_animations.gd` → `resources/animations/survivor_body.res`)

- **23 animações de captura de movimento** (Quaternius UAL 1 e 2, CC0), retargetadas para o esqueleto do personagem:
  - parado, andar, trotar, correr;
  - agachado parado e andando;
  - impulsão, queda e aterrissagem;
  - socos (jab, direto e gancho);
  - golpes recebidos (peito, cabeça e recuo);
  - interagir, pegar, empurrar, consumir, abrir recipiente, andar carregando, morte e levantar.
- **Retarget por delta no espaço do mundo** (`G = C·D·C⁻¹·G_repouso`, em que `C` é a troca de base anatômica). A altura da pélvis é escalada pela razão entre as alturas das pernas.
- **Medição automática:** a ferramenta mede em cada clipe o comprimento da passada, o quadro de contato do calcanhar esquerdo e os quadros de impacto e contato da mão. Os valores ficam salvos como metadados.
  - A passada da física usa os mesmos números: andar 0,67 m, trotar 1,44 m, correr 1,38 m, agachado 0,70 m. Por isso o pé apoiado não desliza.

### 3.3 Animador (`scripts/animation/body_animator.gd`, `BodyAnimator`)

Compõe a pose a cada quadro a partir da física:

1. Repouso.
2. Locomoção pela **fase da passada física**, alinhada ao contato medido. Mistura andar→trotar→correr pela velocidade; para trás, o ciclo é tocado ao contrário; mancar deforma a fase.
3. Agachado pela altura real da cápsula.
4. Ar: impulsão e queda pela velocidade vertical. O voo é reconhecido pelo contato real com o chão; saliências do terreno não disparam a pose.
5. Camadas com eventos (`hit`, `contact`) e "segurar" (golpe carregado). Golpes, ferimentos leves e interação afetam só do peito para cima, e as pernas continuam correndo.

Ajustes procedurais:

- a pélvis gira para o lado do movimento lateral e o tronco gira de volta;
- tronco e pescoço dobram com a inclinação do olhar, distribuídos de 5% a 40% da coluna até a cabeça;
- em terceira pessoa, a cabeça acompanha a câmera.

Reações:

- aterrissagem proporcional ao impacto;
- ferimentos proporcionais ao dano: peito abaixo de 15, cabeça de 15 a 30, recuo do corpo inteiro a partir de 30.

**Erro grave encontrado e corrigido nesta etapa:** as poses intermediárias da mistura começavam na rotação identidade. O osso `root`, que não tem trilha e está girado −90° no repouso, era puxado para a identidade quando a locomoção entrava, e o corpo inteiro tombava 90° para a frente ao correr. Agora toda amostra parte da pose de repouso. Há um teste de regressão para isso.

### 3.4 Câmera (`scripts/camera/camera_rig.gd`, `PlayerCameraRig`)

Um único `Camera3D`, posicionado a cada quadro pela mistura de duas poses.

- **Primeira pessoa:** nos olhos.
  - Combina o ponto estável da física (com os efeitos de passada e aterrissagem) e a cabeça animada, em 55%, suavizada.
  - Ao olhar para baixo a câmera avança até 22 cm, o que mostra o peito e as pernas em vez do pescoço.
  - Um raio do centro da cápsula impede o olho de atravessar paredes quando o tronco se inclina.
- **Terceira pessoa:** órbita sobre o ombro direito.
  - Distância de 2,4 m, ajustável de 1,3 a 4,0 m pela roda do mouse.
  - Pivô a 1,55 m de pé e 1,0 m agachado.
  - Ganha 0,35 m de distância na corrida.
  - Parado, a câmera orbita livre e o corpo não gira; andando, o corpo vira suavemente (540°/s) para a direção do movimento. Golpes e interação viram o corpo para a mira.
- **Transição de 0,5 s em curva *smootherstep*:** posição, altura, distância e orientação interpolam juntas.
  - A direção do olhar é mantida e o personagem não se move.
  - A cabeça só aparece quando a câmera já se afastou 35% do caminho.
- **Colisão:** o braço da câmera é varrido por uma esfera de 18 cm a partir dos olhos, que ficam dentro da cápsula, então a varredura nunca começa dentro de uma parede.
  - Isso acontece em todo quadro, inclusive durante a transição.
  - Contra um obstáculo a câmera encurta na hora; quando há espaço, volta suavemente.
- **Controles:**
  - teclado `V`, gamepad *Back*;
  - na tela, botão **1ª P / 3ª P** no canto superior direito, com anel dourado no modo ativo e pulso de confirmação na troca;
  - aviso discreto "Primeira pessoa" / "Terceira pessoa" no topo da tela.
  - Dá para usar com o dedo no direcional, porque cada dedo tem seu destino.

### 3.5 Morte e ragdoll (`scripts/player/player_death.gd`)

- **Na morte:**
  - a cápsula deixa de colidir;
  - os ossos físicos assumem a pose atual e herdam a velocidade do personagem;
  - o tronco recebe o impulso do golpe que matou (0,8 kg·m/s por ponto de dano, até 80);
  - a câmera segue a cabeça física: presa a ela em primeira pessoa, orbitando o corpo em terceira.
- **Em vida o simulador fica desligado.** Ativo, ele sobrescreveria a pose animada com a dos ossos físicos.
- **Renascer** desliga a simulação, devolve a pose animada, a vida, a câmera e o controle.

### 3.6 Cenário de demonstração (`scenes/demo/demo_forest.tscn`, cena principal)

Gerado por `tools/build_demo_map.gd`: clareira com um posto militar abandonado numa floresta de coníferas.

- **Terreno** de 160 × 160 m com relevo por ruído, achatado na clareira e ao longo de uma estrada de terra. A colisão usa a malha exata.
  - Shader de 3 camadas PBR (chão de floresta, grama, lama/estrada), misturadas pela "altura" das texturas para a lama entrar nas frestas da grama.
  - Variação de tom em grande escala, coordenadas no plano do mundo e rugosidade/especular de solo natural.
- **Floresta de 900 abetos.** Impostores renderizados do modelo *Fir Sapling Medium* (2,3 M polígonos, que não vai para o jogo) em um atlas 3 × 3, com três variantes de altura.
  - Cada árvore são 3 planos cruzados com vento, normais esféricas e translucidez, mais um tronco 3D com casca de pinheiro e colisão cilíndrica.
  - As instâncias são montadas em tempo de execução (`ScatterInstances`).
- **Posto militar:** barreiras de concreto, caixotes, galões, tambores, barris, pneus, latas, caixa elétrica, pé de cabra, facão e machado, todos modelos PBR da Poly Haven.
  - Objetos soltos são corpos rígidos com massa real e colisão convexa gerada da malha.
- **Fogueira interativa** (USAR acende/apaga) com luz que tremula de forma irregular, chamas e fumaça.
- **Arame farpado** com dano (o perigo da etapa 3).
- Pedras com musgo, tocos, tronco caído, arbustos e samambaias.
- **Luz e atmosfera:**
  - céu encoberto procedural;
  - sol de manhã com sombras em 2 cascatas até 55 m;
  - neblina de distância com perspectiva aérea, tom ACES, brilho leve e ajuste de saturação.

### 3.7 Interface

- **Sinais vitais** no canto superior esquerdo: VIDA e FÔLEGO, barras finas com bordas arredondadas. O fôlego some quando está cheio. Aviso de perna ferida.
- **Mira** discreta com contorno.
- **Aviso de objeto interagível** ("USAR Acender a fogueira").
- **Clarão de dano**, e pulso vermelho com a vida baixa.
- **Tela de morte** com a causa e o botão RENASCER.
- **Painel de depuração** escondido por padrão (F3 mostra).

### 3.8 Texturas e desempenho no Android

- As 103 texturas 3D passaram a ser importadas com **mipmaps** e **compressão de vídeo** (ETC2/ASTC no Android, S3TC/BPTC no PC).
  - Mapas normais usam a compressão própria para normais.
  - Antes eram imagens sem compressão e sem mipmaps: cintilavam à distância e ocupavam várias vezes mais memória de vídeo.
- **Árvores** são 6 triângulos cada. Os modelos de objetos usam o LOD automático do importador do Godot.
- **Animador:** cerca de 0,2 ms por quadro no teste de desempenho, com locomoção, mancar e golpe ativos nos 65 ossos.

### 3.9 Correções encontradas durante a etapa

| Problema | Causa | Correção |
|---|---|---|
| Corpo tombado 90° ao correr | Mistura partia da identidade para ossos sem trilha | Amostras partem da pose de repouso |
| Floresta invisível (só o céu mostrava árvores) | O servidor de renderização sem janela não guarda o buffer de `MultiMesh`, então a cena era salva vazia | `ScatterInstances` guarda as transformações e monta o `MultiMesh` no `_ready` |
| Céu com troncos "pendurados" sobre a floresta | HDRI de floresta atrás de árvores 3D | Céu procedural encoberto |
| Chão distante esbranquiçado | Reflexo do céu claro em ângulo rasante (Fresnel) e falta de mipmaps | Rugosidade 0,82–1,0, especular 0,25, mipmaps |
| Pose de salto aparecia tarde | O estado AIRBORNE só muda após a tolerância de borda | Detecção pelo contato real com o chão, mantida até aterrissar |

## 4. Testes

`tests/animation_tests.gd` foi reescrito para a nova arquitetura e tem **158 verificações**. `tests/movement_tests.gd` continua com **123**. Todas passam no Godot 4.5.1 e no 4.7.1.

Cenários obrigatórios da câmera:

| # | Cenário | O que é verificado |
|---|---|---|
| 1 | Alternar parado | Personagem não se move (0,000 m). Transição em 0,5 s. Maior salto por quadro 0,155 m e variação máxima 0,016 m/quadro (sem trancos). Câmera atrás, acima e sobre o ombro (0,38; 1,55; 2,40 m). Mesma direção de olhar. Corpo inteiro visível. Volta suave aos olhos |
| 2 | Alternar andando | Velocidade 1,50 → 1,50 m/s; locomoção continua; sem trancos |
| 3 | Alternar correndo | Continua correndo a 5,80 m/s; sem trancos; a câmera se afasta na corrida |
| 4 | Alternar agachado | Pivô desce de 1,55 m para 1,00 m. Continua agachado. Primeira pessoa na altura dos olhos agachados (0,98 m) |
| 5 | Alternar no combate | O soco iniciado em 1ª pessoa acerta durante a transição; em 3ª pessoa o golpe sai na direção da mira |
| 6 | Perto de paredes | A câmera nunca passa da parede (folga mínima de 0,18 m). O braço encurta e a distância volta suavemente longe dela. Em primeira pessoa encostado, o olho fica do lado de cá |
| 7 | Girar durante a transição | Sem saltos (variação 0,018 m/quadro). Ao fim olha na direção da vista e orbita centrada atrás. Parado, girar a câmera não gira o corpo; andando, o corpo vira |
| 8 | Animações sincronizadas | Depois de 3 trocas, os pés seguem em fase com os passos físicos. Em 3ª pessoa a cabeça está visível e as malhas de 1ª pessoa escondidas (sem braços duplicados) |

Outros testes da bateria:

- corpo em pé em todas as velocidades nas duas câmeras (regressão do tombo);
- pé que pisa à frente em cada contato físico;
- passada da física igual à da animação;
- peso do agachar igual à altura da cápsula;
- salto, queda e aterrissagem;
- reações por dano;
- mancar;
- interação no quadro de contato da mão (quadro 32 de 33 previstos);
- soco no quadro de impacto (quadro 8, evento em 0,17 s) e sequência um-dois alternando as mãos;
- golpe carregado;
- caixa empurrada pelo impulso físico do soco;
- recuo ao socar a parede;
- arame farpado;
- botão de câmera no toque, usado enquanto o direcional anda;
- ragdoll nas duas câmeras: o corpo cai e é empurrado na direção do golpe, a câmera segue e o renascer restaura tudo;
- desempenho.

## 5. Limitações honestas e próximos passos

- **Proporções do personagem:** a versão gratuita (CC0) do pacote de personagens só tem as proporções "Superhero", um homem bem musculoso. As proporções "Regular" estão só na versão paga. Trocar a malha não muda nada no código: o esqueleto é o mesmo.
- **Roupas** são geradas da malha do corpo. Ficam justas, sem dobras de tecido nem bolsos; peças modeladas à parte são o próximo nível.
- **Animações:** a biblioteca CC0 não tem andar agachado para os lados, nem virar no lugar com os pés, nem animações de armas. A torção da pélvis cobre o lateral. As animações de armas entram com a etapa de armas.
- **Ragdoll só na morte.** Mistura física parcial em golpes fortes está planejada para a etapa de ragdoll e reações.
- **Árvores são impostores:** de perto, no tronco, nota-se que a copa é plana. Árvores 3D com LOD exigem modelos leves com licença livre, ainda não encontrados com qualidade suficiente.
- **Pedras e tronco caído da Poly Haven** são densos (100 mil+ polígonos na malha original). O importador gera LOD automático; versões reduzidas fazem parte da etapa de otimização Android, depois dos testes em aparelho.
- **Os testes rodam sem tela.** O visual foi conferido em capturas renderizadas no container (OpenGL); a validação final de desempenho precisa de aparelho Android real.
