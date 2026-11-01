# Procedência e licenças dos assets

Regra do projeto: cada recurso tem a licença verificada **por arquivo** na fonte original antes de entrar no repositório. Recursos sem licença identificável, extraídos de jogos comerciais ou com restrição incompatível com o uso pretendido não são aceitos. Como este repositório é **público**, recursos cuja licença proíbe redistribuir os arquivos brutos também ficam de fora.

## Em uso no jogo

| Recurso | Autor | Origem | Licença | Observação |
|---|---|---|---|---|
| Braços em primeira pessoa (malha, esqueleto, 19 animações) | Projeto Último Amanhecer | gerados por `tools/build_fp_arms.gd` | do projeto | autoria própria |
| Shaders `dev_grid` e `viewmodel` | Projeto Último Amanhecer | `resources/materials/` | do projeto | autoria própria |
| Ícone `icon.svg` | Projeto Último Amanhecer | raiz | do projeto | autoria própria |
| Cenário de calibração | Projeto Último Amanhecer | `tools/build_test_gym.gd` | do projeto | primitivas do Godot |

Nenhum asset de terceiros está incluído no repositório nem no APK.

## Aprovados para as próximas etapas (verificados em 01/11/2026)

| Recurso | Autor | Link | Licença verificada | Conteúdo | Formato / tamanho | Godot 4 | Uso comercial | Atribuição | Restrições | Uso previsto |
|---|---|---|---|---|---|---|---|---|---|---|
| Universal Animation Library (Standard) | Quaternius | https://opengameart.org/content/universal-animation-library | CC0 1.0 (página do OpenGameArt e `License.txt` dentro do pacote) | 46 animações de corpo inteiro (andar, trotar, correr, agachar, saltar, socos, golpe na cabeça e no peito, morte, interagir…) + manequim | GLB para Godot (6,7 MB) e FBX; zip de 14,5 MB | sim (GLB próprio para Godot, esqueleto humanoide) | sim | não exigida (o autor pede apoio opcional) | nenhuma | corpo inteiro visível, sombras do jogador, NPCs |
| Universal Animation Library 2 (Standard) | Quaternius | https://opengameart.org/content/universal-animation-library-2 | CC0 (página do OpenGameArt) | 130+ animações, incluindo **locomoção de zumbi**, combos corpo a corpo e parkour | zip de 10,3 MB | sim (mesmo esqueleto) | sim | não exigida | nenhuma | IA e animações de zumbis |

## Avaliados e rejeitados

| Recurso | Motivo |
|---|---|
| Mixamo (Adobe) | Os termos permitem usar em jogos, mas proíbem redistribuir os arquivos brutos de personagens e animações; num repositório público, versioná-los seria redistribuição. Só poderia ser usado num repositório privado, baixado por quem tem a conta Adobe. |
| "fps arms (rigged only)", OpenGameArt (autor: para), CC0 | Licença compatível, mas só tem rig, sem animações; foi substituído pelo rig próprio. |
| "LowPoly Animated Sword (W/12 Animations)", OpenGameArt (autor: zisongbr), CC0 | Licença compatível, mas são animações de espada só em `.blend`; serão reavaliadas na etapa de armas brancas. |
| Low World first-person arms (itch.io) | Não é CC0 e estava indisponível para download na verificação. |

## Como adicionar um asset

1. Baixar da fonte original e conferir a licença na página e nos arquivos do pacote.
2. Colocar em `assets/<categoria>/<nome>/` junto com o arquivo de licença original.
3. Registrar aqui: nome, autor, link, licença, arquivos, formato, tamanho, compatibilidade, uso comercial, atribuição e restrições.
4. Se a licença exigir atribuição, incluir também na tela de créditos do jogo.
