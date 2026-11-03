# Último Amanhecer

Sobrevivência com zumbis em primeira e terceira pessoa (inspirado em DayZ), feito em **Godot 4.5+** (GDScript) para **Android**, com suporte futuro a PC.

## ⬇️ Baixar o jogo (Android)

**[UltimoAmanhecer.apk — versão mais nova](https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.apk)**

Se o Chrome do Android travar no .apk: **[UltimoAmanhecer.zip](https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.zip)**.

Gerado automaticamente a cada atualização, só depois de todos os testes passarem. Instalação e detalhes: [`docs/DOWNLOAD.md`](docs/DOWNLOAD.md).

## Documentação

- Arquitetura e plano de etapas: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
- Etapa 1, personagem e movimento (concluída): [`docs/ETAPA_01_PERSONAGEM.md`](docs/ETAPA_01_PERSONAGEM.md)
- Etapa 2, física avançada de movimentação (concluída): [`docs/ETAPA_02_FISICA_AVANCADA.md`](docs/ETAPA_02_FISICA_AVANCADA.md)
- Etapa 3, animações em primeira pessoa (concluída; braços substituídos na etapa 4): [`docs/ETAPA_03_ANIMACOES.md`](docs/ETAPA_03_ANIMACOES.md)
- Etapa 4, reconstrução visual, corpo completo e câmera 1ª/3ª pessoa (concluída): [`docs/ETAPA_04_RECONSTRUCAO.md`](docs/ETAPA_04_RECONSTRUCAO.md)
- Etapa 5, correção profunda da jogabilidade: toque, personagem, animação, física e combate (concluída): [`docs/ETAPA_05_JOGABILIDADE.md`](docs/ETAPA_05_JOGABILIDADE.md)
- Etapa 6, seu personagem, sons, mapa de 400 m, defesa por toque e pés no terreno (concluída): [`docs/ETAPA_06_SOBREVIVENTE_SONS_MAPA.md`](docs/ETAPA_06_SOBREVIVENTE_SONS_MAPA.md)
- Etapa 7, picareta, machado e taco com pregos, mundo procedural infinito por pedaços com cavernas, rodovias abandonadas e som só do vento (concluída): [`docs/ETAPA_07_ARMAS_MUNDO_PROCEDURAL.md`](docs/ETAPA_07_ARMAS_MUNDO_PROCEDURAL.md)
- Etapa 8, lanterna corrigida, cavernas exploráveis, mochila com PEGAR e barra rápida, corte de árvores, mineração, zumbis e durabilidade (concluída): [`docs/ETAPA_08_COLETA_CAVERNAS.md`](docs/ETAPA_08_COLETA_CAVERNAS.md)
- Etapa 9, menu inicial, mundos com semente salvos no aparelho, personagem personalizável, mochila em grade com bancada e receitas, novas ferramentas e armaduras, escalada de encostas, biomas, vilas e cidades abandonadas, zumbis variados (concluída): [`docs/ETAPA_09_MUNDO_VIVO.md`](docs/ETAPA_09_MUNDO_VIVO.md)
- Procedência e licenças dos assets: [`ASSET_LICENSES.md`](ASSET_LICENSES.md)

## Começar

1. Abra a pasta no Godot 4.5 ou superior e pressione F5: a cena principal é o mundo procedural (`scenes/world/mundo.tscn`), gerado por pedaços em volta do jogador; o mapa fixo da clareira continua em `scenes/demo/demo_forest.tscn`. `V` alterna 1ª/3ª pessoa, a roda do mouse ajusta a distância, botão esquerdo ataca (segurar = golpe carregado), botão direito ou `Q` ergue/abaixa a guarda, `E` usa/pega, `1`–`4` escolhem a ferramenta, `G` solta, `I`/`Tab` abre a mochila, F3 mostra o painel de depuração. A cena de calibração da física fica em `scenes/test/movement_test_gym.tscn`.
2. Para rodar os testes automatizados:

```
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn
```
