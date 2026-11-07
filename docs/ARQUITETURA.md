# Arquitetura do motor

```
main.js ─ Game
 ├─ Renderer (engine/renderer.js)      forward PBR, UBO "Scene", sombras em cascata (array), passes shadow/main/transparente
 │    ├─ shaders.js                    uber-shader por defines (INST, SKINNED, LAYERED, WIND, ALPHA_TEST…), céu, terreno, água, grama, partículas
 │    ├─ gl.js                         contexto, Program, Mesh, InstanceBuffer, texturas/arrays, MeshBuilder
 │    └─ atmosphere.js                 hora do dia + clima → sol, céu, névoa, vento, exposição
 ├─ Physics (engine/physics.js)        grade espacial de colisores, heightfield, cápsula, corpos rígidos, raycast, balística
 ├─ Skeleton (engine/anim.js)          FK, blend, IK de 2 ossos, ganchos em espaço de mundo
 ├─ Particles / AudioEngine / Input
 └─ Jogo: worldgen → Terrain, Vegetation, Level(world.js/buildings.js), Player, WeaponSystem, Character, Vehicle, UI
```

## Mundo (2 × 2 km)
`worldgen.js` gera, de forma determinística (semente 1337): relevo (fBm + cordilheira ridged + bordas elevadas), lago em bacia, rio com canal e planície, plateaus das vilas, estradas com terraplenagem, pontes, mapa de normais e dois *splat maps* (grama, floresta, terra, rocha, areia, cascalho, asfalto, umidade).
`terrain.js` envia a altura como textura `R32F` e desenha 16×16 chunks de 128 m com grades de 64/32/16/8/4 células (LOD por distância + saias contra frestas); o fragment shader mistura 7 camadas de um `texture array` perto da câmera e usa cor média longe.

## Vegetação
`vegetation.js`: 3 espécies procedurais × 4 LODs; colocação por grade jittered (~7,5 m) com máscara de floresta; células de 64 m com `InstanceBuffer` por espécie, super-células de 256 m para o LOD distante; cobertura de solo (samambaia, arbusto, pedras, tocos) com modelos CC0 "assados" por variante; grama 100% na GPU (índice da instância → posição, densidade do splat, altura da textura, vento).

## Física
- **Colisão estática:** caixas orientadas (yaw), cilindros e o heightfield; grade de 16 m.
- **Personagem:** cápsula vs. colisores, degraus de 0,55 m, inclinação máxima, água (nado/vadeio), queda com dano.
- **Corpos rígidos:** integração semi-implícita a 120 Hz; contato por vértices da caixa contra terreno/colisores com impulso normal + atrito (Coulomb) + restituição; sono automático; empuxo na água.
- **Balística:** subpassos de ≤20 m; `a = -k·|v_rel|·v_rel - g`; vento relativo; raycast por segmento; penetração por material/espessura. Medido: queda de 0,09 / 0,35 / 0,82 m a 100 / 200 / 300 m para 810 m/s (k = 0,00075).
- **Veículo:** 4 raios de suspensão contra o terreno/colisores, mola + amortecedor, força lateral limitada por μ·N, tração, freio e freio de mão aplicados como impulsos no corpo rígido.

## Android
`MainActivity` é um `WebView` imersivo que serve `assets/` do APK em `https://appassets.local/` (origem segura → módulos ES, `fetch`, WebAudio), pede o maior modo de atualização da tela (até 120 Hz), ativa o modo de desempenho sustentado e mapeia o botão Voltar para o menu do jogo.
