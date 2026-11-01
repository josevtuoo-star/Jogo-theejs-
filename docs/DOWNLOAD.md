# Baixar e instalar o jogo

## Link direto (Android)

**https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.apk**

Alternativa em .zip (use se o navegador travar no APK):
**https://github.com/josevtuoo-star/Jogo-theejs-/releases/latest/download/UltimoAmanhecer.zip**

Os links apontam sempre para a build mais nova. Todas as versões ficam em
https://github.com/josevtuoo-star/Jogo-theejs-/releases

## Instalar no celular

1. Abra o link no navegador do celular e baixe o APK (~26 MB).
2. Toque no arquivo baixado. Na primeira vez, o Android pede para permitir a instalação de apps desta fonte (navegador ou gerenciador de arquivos): permita.
3. Requisitos: Android 7.0 ou superior e processador de 64 bits (arm64). Vulkan é recomendado (renderizador Mobile do Godot); sem Vulkan, o Godot tenta o modo de compatibilidade OpenGL.
4. As versões seguintes instalam por cima da anterior, porque usam a mesma chave de assinatura.

### Se o download travar em 100% ("Fazendo o download…")

O Chrome do Android às vezes segura arquivos `.apk` no fim do download, na verificação de segurança. O arquivo costuma já estar salvo:

1. Abra o app **Arquivos** (ou "Meus arquivos") → **Downloads** e toque em `UltimoAmanhecer.apk`.
2. Se ele não estiver lá, baixe o **.zip** acima. No app Arquivos, toque nele → **Extrair**, depois toque no `UltimoAmanhecer.apk` extraído.
3. Outra opção é baixar por outro navegador (Firefox, Samsung Internet).

O jogo abre na área de calibração. Controles de toque:
- direcional no lado esquerdo: pouco inclinado anda, todo inclinado trota, além da borda para frente corre;
- arrastar o lado direito da tela: olhar;
- botões PULAR e AGACHAR;
- ATACAR: toque rápido dá um soco, segurar carrega um golpe;
- USAR: interagir e renascer.

## Como a build é feita

O workflow `.github/workflows/android.yml` roda a cada push que altere o jogo (mudanças só em documentação não geram build):

1. baixa o Godot 4.5.1 e os templates de Android (com cache);
2. importa o projeto e roda **todos os testes de física**; se algum falhar, nenhum APK é publicado;
3. exporta o APK em modo release (arm64-v8a), com versão `0.2.<número da build>`;
4. confere a assinatura com `apksigner verify`;
5. cria uma Release `v0.2.<n>` marcada como a mais recente.

Para gerar uma build sem alterar código: aba **Actions** → **APK Android** → **Run workflow**.

## Assinatura

Sem configuração extra, as builds usam a chave de **teste** `export/android_teste.keystore` (alias e senha `ultimoamanhecer`). Como o repositório é público, essa chave serve só para testes e nunca deve ser usada na Play Store.

Para usar uma chave própria e secreta:

1. Gere uma chave: `keytool -genkeypair -keystore minha.keystore -alias MEU_ALIAS -keyalg RSA -keysize 2048 -validity 10000`
2. No GitHub, abra **Settings → Secrets and variables → Actions** e crie:
   - `ANDROID_KEYSTORE_BASE64`: saída de `base64 -w0 minha.keystore`
   - `ANDROID_KEY_ALIAS`: o alias
   - `ANDROID_KEYSTORE_PASSWORD`: a senha (a mesma para o arquivo e para a chave)
3. A próxima build passa a usar essa chave. O APK novo terá outra assinatura: desinstale a versão de teste uma vez antes de instalar.

## Exportar localmente

Com os templates do Godot 4.5.1 e o Android SDK configurados no editor (Editor → Editor Settings → Export → Android), use Projeto → Exportar → Android. Pela linha de comando:

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=export/android_teste.keystore \
GODOT_ANDROID_KEYSTORE_RELEASE_USER=ultimoamanhecer \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=ultimoamanhecer \
godot --headless --path . --export-release "Android" builds/android/UltimoAmanhecer.apk
```
