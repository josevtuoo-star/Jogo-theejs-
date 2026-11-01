# Último Amanhecer

Sobrevivência em primeira pessoa com zumbis, feito em **Godot 4.5+** (GDScript) para **Android**, com suporte futuro a PC.

## ⬇️ Baixar o jogo (Android)

**[UltimoAmanhecer.apk — versão mais nova](https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.apk)**

Gerado automaticamente a cada atualização, só depois de todos os testes passarem. Instalação e detalhes: [`docs/DOWNLOAD.md`](docs/DOWNLOAD.md).

## Documentação

- Arquitetura e plano de etapas: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
- Etapa 1, personagem e movimento (concluída): [`docs/ETAPA_01_PERSONAGEM.md`](docs/ETAPA_01_PERSONAGEM.md)
- Etapa 2, física avançada de movimentação (concluída): [`docs/ETAPA_02_FISICA_AVANCADA.md`](docs/ETAPA_02_FISICA_AVANCADA.md)
- Etapa 3, animações em primeira pessoa (concluída): [`docs/ETAPA_03_ANIMACOES.md`](docs/ETAPA_03_ANIMACOES.md)
- Procedência e licenças dos assets: [`ASSET_LICENSES.md`](ASSET_LICENSES.md)

## Começar

1. Abra a pasta no Godot 4.5 ou superior e pressione F5 para entrar na cena de calibração do movimento.
2. Para rodar os testes automatizados:

```
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn
```
