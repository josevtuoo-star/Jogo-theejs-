# Etapa 10 — Mundo quebrável, dia e noite, interiores

Pedido do dono do projeto (com capturas de tela): remover a seta da caverna;
o texto "PEGAR" que fica sempre na tela; coisas voando, pedras e objetos que
não dá para quebrar ("tudo quebra igual Minecraft"); casas com interiores;
ferramentas mal posicionadas na mão; animações de combate, do machado na
árvore e da picareta na pedra; distância de renderização melhor ou nas
configurações; a névoa não pode ser permanente; ciclo de dia e noite
funcional.

## 1. Correções

- **Seta da caverna**: removida (`cave_compass.gd` apagado).
- **"PEGAR" preso na tela**: o objeto pego era liberado, mas o foco ainda
  guardava a referência: um objeto liberado compara igual a `null`, então a
  checagem `focused != null` falhava. Agora o foco guarda o id da instância
  (`is_instance_id_valid`) e some quando o objeto some.
- **Coisas voando**: os 2.910 pés de árvore de um raio de 200 m ficaram
  assentados na conta do terreno, mas junto das bocas das rampas de caverna
  a malha arredonda a quina do corte e o objeto ficava no ar. `_solid_ground`
  agora confere também quatro pontos a 2 m em volta.
- **Copas pontilhadas**: o esmaecimento das árvores perto da câmera ficou
  mais curto (só some o que está a menos de ~1,5 m ou visto de lado).
- **Zumbi magro**: escala não uniforme não é aceita pelos ossos físicos
  (Jolt); passou a escala uniforme.

## 2. Tudo quebra (como no Minecraft)

`ChunkResources.PROP_RULES`: cada objeto tem material, resistência e o que
solta.

| Material | Objetos | Ferramenta | Solta |
|---|---|---|---|
| Pedra | rochedos, pedras com musgo, barreiras, estalagmites | picareta (pé de cabra devagar) | pedras |
| Madeira | tocos, troncos, caixotes | machado e facão (outras ferramentas e mãos, devagar) | madeira ou tábuas |
| Metal | barris, lixeiras, postes, carcaças | pé de cabra, picareta, machado | ferro |
| Mato | samambaias, arbustos, mato, galhos | qualquer coisa, inclusive as mãos | gravetos |

Cada golpe solta lascas e som do material; o objeto treme; ao ceder, some
com estilhaços e solta os recursos coletáveis (PEGAR). Nada quebrado volta ao
recarregar o pedaço (chave `p_`, `c_` no salvamento). O mato só recebe golpes
(camada de alvos): o jogador continua atravessando as plantas.

**Terreno**: golpes de picareta no chão acumulam até ceder e abrir um buraco
de ~3 m (esfera subtraída do campo de densidade do pedaço, que é refeito em
segundo plano e trocado quando pronto, sem soltar o que está no chão). As
escavações vão para o salvamento do mundo.

## 3. Ferramentas na mão e animações

- **Pegada de duas mãos**: a mão esquerda vai ao cabo por IK (com correção do
  centro do punho, que é o que segura o cabo): machados, picaretas, pé de
  cabra e taco com as duas mãos; lança com a esquerda à frente; faca, facão e
  tocha numa mão só. A mão solta o cabo ao pegar coisas, ao apanhar e ao
  escalar.
- **Orientação**: o lado que golpeia (lâmina do machado, ponta da picareta)
  agora aponta para onde apontam os nós dos dedos, como ao empunhar um
  martelo, e não para o lado da palma.
- **Golpes por ferramenta** (`WeaponData.light_clip`): machados, picaretas e
  pé de cabra descem de cima para baixo; o taco e o facão golpeiam de lado; a
  lança estoca. Diante de árvore ou madeira vale o corte de lenhador; diante
  de rocha, metal ou chão (picareta), o golpe de picareta. A direita sobe no
  cabo (`grip_shift`) e o alcance acompanha.
- **Primeira pessoa em repouso**: a ferramenta aparece embaixo à direita,
  inclinada para cima, com a cabeça à vista.

## 4. Dia e noite, clima e névoa

`SkyCycle`: o sol nasce a leste às 6 h, passa alto ao meio-dia e se põe às
18 h; à noite a lua dá luz fraca e azulada e o céu mostra estrelas; amanhecer
e entardecer alaranjados; crepúsculo longo. Luz difusa, exposição, cor do
céu e da névoa seguem a hora. A lanterna de cabeça acende também à noite,
ao ar livre.

**Clima** (muda sozinho a cada 3 a 9 horas de jogo): céu limpo, nublado,
neblina (mais comum de manhã) e chuva (gotas em volta da câmera e vento
mais forte). **A névoa deixou de ser permanente**: é por profundidade e se
ajusta à distância de visão (no tempo limpo só esconde a borda do mundo; na
neblina fecha a ~45 m).

## 5. Configurações

Menu inicial e menu de pausa: **distância de visão** (curta a máxima, 2 a 6
pedaços de 32 m), **sombras** (desligadas, baixas, altas), **duração do dia**
(12, 24, 48, 96 min) e **sensibilidade da câmera**. Valem na hora e ficam
gravadas. O menu de pausa mostra a hora e o clima.

## 6. Casas e prédios com interior

- **Casas** (vilas): paredes com vão de porta (na frente, virada para o
  centro da vila) e janelas abertas, piso, parede interna com passagem e, nas
  casas de dois andares, **escada** e piso de cima com o vão dela; teto e
  telhado. Dá para entrar e subir.
- **Prédios** (cidades): o térreo é aberto (porta e vitrines); os andares de
  cima são fechados, com janelas pintadas na fachada.
- **Colisão**: uma caixa por pedaço de parede, piso, teto e rampa da escada.
- **Dentro**: caixotes e barris (quebráveis), saque (ferro, tábuas, carvão,
  gravetos e, às vezes, uma arma) e, às vezes, um zumbi preso.

## 7. Testes

| Bateria | Verificações | Godot 4.5.1 | Godot 4.7.1 |
|---|---|---|---|
| `tests/animation_tests.gd` | 479 | passam | passam |
| `tests/movement_tests.gd` | 126 | passam | passam |

Novos: tudo quebra (rochedo com picareta e não com as mãos, mato com as mãos,
carcaça com pé de cabra, não volta ao recarregar), cavar o terreno (cede em 2
golpes, o buraco aparece e vai para o salvamento), casa com interior (entra
pela porta, a parede dos fundos segura, sobe a escada), dia e noite (sol,
escuridão, passagem do tempo, neblina, chuva, salvamento) e a distância de
visão nas configurações.

## 8. Limitações honestas

- Os andares de cima dos prédios da cidade ainda são fechados.
- A escavação é por buracos esféricos de ~3 m (a malha do terreno tem 2 m de
  resolução), não blocos de 1 m; ainda não dá para colocar blocos (próxima
  etapa).
- Mais distância de visão pesa no celular: o padrão é médio (3 pedaços).
- As animações de duas mãos foram conferidas em imagens; falta testar a
  sensação no aparelho.
