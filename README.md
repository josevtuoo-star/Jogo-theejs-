# Último Amanhecer

Sobrevivência em primeira pessoa com zumbis, feito em **Godot 4.5+** (GDScript) para **Android**, com suporte futuro a PC.

- Arquitetura e plano de etapas: [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md)
- Etapa 1, personagem e movimento (concluída): [`docs/ETAPA_01_PERSONAGEM.md`](docs/ETAPA_01_PERSONAGEM.md)

## Começar

1. Abra a pasta no Godot 4.5 ou superior e pressione F5 para entrar na cena de calibração do movimento.
2. Para rodar os testes automatizados:

```
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```
