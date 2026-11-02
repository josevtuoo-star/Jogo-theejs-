# Etapa 6 — Seu personagem, sons, mapa ampliado e jogabilidade

Pedidos do dono do projeto (02/11/2026):
- usar o personagem do arquivo `Sobrevivente.fbx`;
- remover a resistência por enquanto;
- defesa com um toque, sem precisar segurar;
- animações mais realistas;
- melhorar câmera em primeira pessoa, controles e jogabilidade;
- aumentar o mapa sem perder a qualidade dos detalhes;
- sons realistas para cada ação.

## 1. Personagem do `Sobrevivente.fbx`

O modelo enviado tem:
- uma malha de 18,4 mil vértices com 23 materiais de cor: pele, barba, cabelo, olhos, gorro, jaqueta com zíper, metal e cordão, calça cargo, botas com cadarço e sola, luvas e sujeira;
- esqueleto de 65 ossos na convenção Mixamo (`Hips`, `Spine`, `LeftArm`…);
- pose em T.

Como foi integrado:
- **Nomes dos ossos** (`tools/rig_names.gd`): cada osso Mixamo é renomeado para o nome usado pelo jogo (`Hips→pelvis`, `LeftArm→upperarm_l`, `LeftHandIndex1→index_01_l`…), e a pele (Skin) também. Animador, combate, ragdoll e testes funcionam sem mudança. Trocar de personagem de novo só exige esse mapa.
- **Retarget com alinhamento de poses** (`tools/retarget_animations.gd`): o personagem está em T e as fontes de animação não.
  - Antes de aplicar o movimento capturado, cada osso do personagem é girado até a direção que o osso da fonte tem na pose de repouso dela.
  - Sem isso, os braços sairiam 45° mais altos em todas as animações.
  - As 25 animações foram geradas de novo. A passada medida nas pernas do seu personagem foi copiada para a física: andar 0,63 m, trotar 1,39 m, correr 1,35 m, agachado 0,62 m. É o que mantém o pé sem deslizar.
- **Materiais** (`tools/build_survivor.gd`): as cores do modelo viram materiais PBR, com rugosidade e metal por tipo de superfície (tecido, couro, metal, pele, olhos), e as cores um pouco escurecidas para a luz física do jogo.
- **Primeira pessoa:** a cabeça (rosto, gorro, barba, cabelo) é separada do corpo pelos pesos de cabeça e pescoço. Em primeira pessoa ela só projeta sombra.
- **Removidos:** o corpo Quaternius, as roupas e os cabelos anteriores. A pasta do personagem caiu de 34 MB para 400 KB.

## 2. Resistência desligada e defesa com um toque

- **Resistência:** o nó `Stamina` saiu do jogador. Correr, saltar, socar e defender não gastam mais nada, e a barra FÔLEGO some do HUD.
  - O `StaminaComponent` continua no projeto para voltar quando você quiser.
- **Defesa:** um toque em DEFESA ergue a guarda, que fica erguida até outro toque. O botão mostra "GUARDA" enquanto está ativo.
  - Correr abaixa a guarda.
  - Atacar de guarda funciona e, depois do golpe, volta à guarda.

## 3. Animação, câmera e controles

- **Pés no terreno (IK):** o mapa ampliado tem morros.
  - Cada pé procura o chão com um raio, e as pernas se ajustam com IK de dois ossos.
  - A pélvis desce para o pé mais baixo, e o pé apoiado inclina com o terreno.
  - Na rampa de 30° de teste, os tornozelos ficam a 0,115 m e 0,076 m do chão sob cada pé (o valor de repouso é 0,09 m) e a pélvis desce 17,5 cm. No plano não muda nada.
- **Câmera em primeira pessoa mais estável:**
  - a câmera segue a cabeça animada 35% na vertical e só 12% na horizontal (antes eram 55% em tudo), então a mira não balança com a cabeça da captura;
  - o balanço do passo volta a vir da passada física, mais suave;
  - campo de visão de 70° (antes 75°).
- **Toque:**
  - sensibilidade menor para mirar com precisão, com aceleração em arrastos rápidos (até 1,6×) para virar depressa;
  - direcional com zona morta de 12% (o dedo apoiado não anda) e resposta progressiva.
- **Luz da floresta:** a luz ambiente do céu subiu de 0,7 para 1,15. Sob a copa o sol não chega, e a mata densa ficava quase preta; a clareira continua com a mesma aparência.

## 4. Mapa ampliado (160 m → 400 m)

- **Área original intacta:** a ampliação foi feita sem tocar em nada da clareira aprovada.
  - O terreno usa a mesma função de relevo e a mesma grade.
  - A floresta e os objetos originais saem da mesma sequência aleatória; a ampliação usa geradores próprios.
  - Uma comparação automática deu: os 19 objetos do posto, os 37 da natureza e as 900 árvores **idênticos**, e os 6.241 vértices do terreno com **0,0 m** de diferença de altura e textura.
- **6.500 árvores** (900 originais + 5.600 novas) na mesma densidade, divididas em blocos de 40 m.
  - Cada bloco some a 320 m, onde a neblina já esconde; os troncos 3D somem a 75 m. O celular só desenha o que está perto.
- **Vegetação:** 1.600 samambaias e 500 arbustos espalhados, em blocos que somem a 45 m. Mais 70 tocos e troncos caídos com colisão.
- **Novos lugares**, com os mesmos modelos de qualidade da clareira:
  - acampamento de caçadores numa clareira a nordeste: segunda fogueira, caixotes, barris, machado, latas e bancos de tronco;
  - segundo bloqueio na estrada, ao norte: barreiras, caixa elétrica, tambores, pneus, galão, pé de cabra e arame farpado;
  - mirante de pedras num morro a oeste.
- **Estrada:** atravessa o mapa inteiro.

## 5. Sons (95 arquivos, todos CC0)

Licenças e autores estão em `ASSET_LICENSES.md` (seção Sons) e a origem de cada arquivo em `assets/audio/SOURCES.md`.

Os sons são disparados pelos eventos reais do jogo, nunca por tempo fixo:

| Evento | Som |
|---|---|
| Contato físico do pé (sinal `footstep`) | Passo por superfície (terra, grama, gelo, pedra; lama mais grave). O volume segue a intensidade: agachado baixo, correndo alto. A roupa farfalha na corrida |
| Salto e aterrissagem | Esforço e roupa no salto. Aterrissagem com volume pelo impacto |
| Dano e morte | Dor (no máximo a cada 0,6 s; o arame dá dano contínuo), morte e o corpo caindo |
| Golpe | O braço corta o ar no início do golpe. O acerto soa conforme o alvo: corpo, madeira, metal ou parede. Impacto na guarda |
| Objetos físicos | Caixotes, tambores, galões, latas e ferramentas soam ao bater em algo, com volume e tom pela força do choque e pela massa |
| Interação | Interruptor, couro, roupa ao agachar e erguer a guarda |
| Mundo | Fogueira crepitando em 3D quando acesa. Ambiente da floresta com passarinhos que vêm e vão em ondas |

Todos usam variações sorteadas sem repetir e com tom levemente diferente, para não soar mecânico. Os barramentos de áudio são `Efeitos` e `Ambiente`.

## 6. Testes

| Bateria | Verificações | Godot 4.5.1 | Godot 4.7.1 |
|---|---|---|---|
| `tests/animation_tests.gd` | 235 | passam | passam |
| `tests/movement_tests.gd` | 119 | passam | passam |

Novas verificações:
- personagem do FBX com cabeça separada e resistência desligada;
- defesa por toque, no botão e no teclado;
- pés na rampa;
- sons de passo (um por contato), superfície, aterrissagem, soco, dor, morte e corpo caindo;
- zona morta do direcional;
- mapa ampliado: 400 m, 6.500 árvores em blocos com distância, 2 fogueiras, os pontos de interesse e som em todos os 27 objetos soltos.

Na bateria de movimento:
- a corrida agora é ilimitada (6 s a 5,8 m/s);
- a subida reduz a velocidade sem gastar resistência;
- a lama é mais lenta.

## 7. APK e download

- **Tamanho:** os assets de personagem removidos (cerca de 34 MB de texturas) e a textura sem uso saíram do APK. Os sons somam 2,1 MB.
- **Conferência do download:** cada Release traz agora o tamanho exato e o SHA-256 do APK e do ZIP. Se o Android disser "pacote inválido", dá para conferir se o arquivo chegou corrompido.

## 8. Limitações honestas

- **Sons sem audição humana:** escolhi pelas descrições dos autores e conferi duração e volume de cada arquivo, mas não posso ouvi-los. Se algum não combinar, `tools/prepare_audio.py` troca o arquivo de origem numa linha.
- **Animações:** continuam sendo capturas genéricas gratuitas (Quaternius UAL). Pés no terreno, inclinação, pés plantados e passo de ajuste deixam o corpo mais crível. Animações dedicadas (andar de lado, virar no lugar, parar) exigiriam a versão paga ou capturas novas.
- **Materiais do personagem:** o modelo enviado usa cores planas, sem texturas, e o resultado mantém esse estilo low-poly. Texturas pintadas no modelo seriam usadas automaticamente pelo `build_survivor.gd` com pequenas mudanças.
- **Desempenho:** o mapa maior foi feito com blocos e distâncias de desenho pensando no celular, mas a confirmação depende de rodar no seu aparelho.

## 9. Ajustes depois do teste no celular (v0.6.7)

O dono do projeto testou a v0.6.6 no aparelho e apontou quatro problemas: sons artificiais, câmera em primeira pessoa ruim e física da corrida artificial. Na captura de tela, uma mancha verde enorme cobria o canto inferior esquerdo.

### Câmera em primeira pessoa: a mancha verde era a gola da jaqueta vista por dentro

**Causa:** na corrida, a animação capturada e a inclinação levam a cabeça até 0,42 m para a frente e 13 cm para baixo. A câmera seguia a cabeça suavizando uma posição do **mundo**. Com o corpo a 5,8 m/s, o filtro deixava a câmera v/k ≈ 0,26 m para trás, dentro da gola e dos ombros. Um teste novo reproduziu o erro: 0,235 m de afastamento, com a câmera 0,15 m **atrás** da cabeça.

**Correção** (`scripts/camera/camera_rig.gd`): o deslocamento da cabeça é suavizado no **espaço do corpo**. A parte lenta (inclinar, agachar) é seguida inteira, na horizontal e na vertical. Do balanço rápido da passada, só passa uma fração (35% na vertical, quase nada na horizontal), o que mantém a mira estável.

Resultado medido:
- afastamento máximo de 0,07 m dos olhos;
- câmera sempre à frente da cabeça;
- a altura da câmera acompanha os olhos (1,50 m = 1,50 m).

Também mudaram:
- **Campo de visão:** havia uma falha minha na v0.6.6. O FOV de 70° nunca valeu, porque o `CameraEffects` sobrescrevia com 75°. Agora são 70° parado e 76° correndo (sensação de velocidade), com transição suave.
- **Balanço do passo:** menor, e o plano de corte próximo passou de 0,05 para 0,08 m.

### Física da corrida

- **Frenagem:** de 12 para 7 m/s². Da corrida até parar são 2,35 m e 0,8 s, em vez de 0,45 s seco. Do trote são 0,89 m.
  - Os testes antigos fixavam números da versão anterior. Agora conferem a física: d = v²/2a com tolerância de 15%.
- **Arrancada:** de 9 para 7,5 m/s²; chegar à velocidade máxima é mais gradual.
- **Curva na corrida:** em terceira pessoa o corpo vira 45% da velocidade normal (243°/s), então a curva fica aberta.
- **Inclinação do tronco** pela aceleração: no máximo 7° (antes 12°, exagerado).
- **Empurrar objetos:** as pernas empurram pela intenção (direção e velocidade desejadas), não só pela velocidade do instante.
  - Encostado numa caixa, o corpo quase para a cada choque, mas continua fazendo força nela, como uma pessoa empurrando.
  - A arrancada mais suave expôs esse defeito: a caixa de 5 kg andava 0,82 m no Godot 4.7.1 e 1,13 m no 4.5.1. Agora anda 2,45 m e 2,43 m (os dois motores concordam). O bloco de 300 kg continua sem se mexer, porque a aderência da sola limita a força.

### Sons

A causa principal era a **mistura**: na v0.6.6, todos os sons tinham o mesmo volume normalizado. Um passo soava tão alto quanto um soco, e o ambiente ficava baixo.

- **Proporções reais:**
  - passo de -26 dB (agachado) a -10 dB (correndo), bem abaixo do soco;
  - braço cortando o ar baixo;
  - ambiente da floresta presente.
- **Cada som varia** ±2 dB de volume, além do tom.
- **Passo no chão de floresta em duas camadas sorteadas:**
  - calcanhar abafado, o passo do Kenney com filtro passa-baixa, sem o estalo de sola dura;
  - folhas secas, 20 farfalhares de qubodup, CC0, em trechos curtos.
  - Saiu o passo de "areia", que soava a cascalho.
- **Aterrissagem** = os dois pés batendo no chão, com 40 ms de diferença, mais o corpo absorvendo o impacto. Gemido só em quedas fortes.
- **Respiração cansada** (mikeask, CC0) em laço:
  - surge depois de uns 3 s de corrida e cresce com o esforço;
  - some aos poucos parado (cerca de 10 s).
- **Voz:**
  - sem gemido a cada salto;
  - dor só com dano de 8 ou mais e no máximo a cada 1,2 s.
- **Vento** na copa com rajadas, gerado (ruído marrom filtrado), como terceira camada do ambiente.
  - As três camadas (mata, vento, passarinhos) têm ciclos diferentes, então nenhum laço fica óbvio.
- **Reverberação curta de mata** e um leve corte de agudos no barramento de efeitos. Os sons deixam de soar "secos de estúdio".

Testes novos:
- câmera nos olhos e à frente da cabeça correndo;
- FOV abre e volta;
- duas camadas por passo;
- aterrissagem com os dois pés;
- esforço sobe correndo e cai parado.

Os testes de movimento conferem a frenagem pela física.

**Limitação que continua:** escolho e mixo os sons pelas descrições, pela duração, pelo pico e pela loudness medida, mas não consigo ouvi-los. A opinião no aparelho continua sendo a referência; trocar qualquer som é uma linha em `tools/prepare_audio.py`.
