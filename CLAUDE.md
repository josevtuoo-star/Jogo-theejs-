# Instruções para o assistente

- Projeto: Último Amanhecer (Godot 4.5+, GDScript, Android primeiro). Documentação em `docs/`.
- **Sempre** termine cada entrega com o link direto de download do jogo:
  https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.apk
  e a alternativa em .zip (para quando o Chrome do Android travar no .apk):
  https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.zip
  Antes de enviar o link, confirme que o workflow **APK Android** (`.github/workflows/android.yml`) da última alteração terminou com sucesso e que a Release nova foi publicada; informe a versão (`v0.<etapa>.<n>`). Se a build falhar, diga isso e mostre o erro em vez de enviar o link como se estivesse atualizado.
- Rode as duas baterias de testes antes de cada commit:
  `godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn` e
  `godot --headless --path . --fixed-fps 60 res://tests/animation_test_runner.tscn`.
