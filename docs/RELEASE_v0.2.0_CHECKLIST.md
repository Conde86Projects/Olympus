# Checklist de release — Olympus 0.2.0

Marco 0.2.0: composição mobile, janela pequena no Windows, catálogo da
fonte própria, saída direta do vídeo no Android/TV, menus compactos da
TV e padrão visual único (`docs/PADROES_VISUAIS.md`). Commit do marco:
`0d82363`. Testes finais em `docs/TESTES_FINAIS_0.2.0.md`, resultados em
`docs/RESULTADOS_TESTES_0.2.0.md`. `v0.1.0` (`bd3270a`) e as tags
`rc` anteriores ficam intactas.

## Gates (antes da tag)

- [x] Suíte completa verde: 642/642 (`flutter test`) numa cópia limpa
      de `0d82363`.
- [x] `dart analyze` limpo.
- [x] Árvore limpa: nenhuma alteração local pendente (os menus da
      TV entraram em `b940173`).
- [x] `version_consistency_test`: `AppConstants.appVersion` acompanha
      o núcleo do `version:` do pubspec.
- [x] Celular físico validado (Xiaomi 24069PC21G, Android 16).
- [x] Windows validado (125% e 150%, janela pequena e grande).
- [x] TCL validada com APK **release** (BeyondTV, Android 9).

## Consistência das versões

- [x] `pubspec.yaml`: `0.2.0+10`.
- [x] `AppConstants.appVersion`: `0.2.0` (Diagnóstico e Sobre exibem
      este valor).
- [x] APK release instalado na TCL: `versionName=0.2.0`,
      `versionCode=10` (dumpsys).
- [x] Windows release: `ProductVersion`/`FileVersion` `0.2.0+10`.
- [x] SHA-256 do APK release de `0d82363` (97.807.576 bytes,
      `flutter build apk --release`, assinatura de release dedicada),
      instalado na TCL:
  `59AAC37CC5F63FA363E488132B29033DD1A3185E98414DACA762593D4C3D6AA4`.

## O que entra (desde a 0.1.0)

- Windows: janela mínima 480x270, card de uma fileira em janela baixa,
  menus que rolam, minimizar e fechar pelo X gravam a posição, a
  janela some na hora ao fechar.
- Mobile (Android/iOS sem modo TV): navegação inferior, alvos de
  48 dp, toque/toque duplo no player, tela cheia em paisagem, barra de
  gestos respeitada, painel de configurações que cabe deitado.
- Fontes: catálogo navegável e fonte própria de teste (feed
  `mux-smoke`, temporário).
- Android/TV: saída direta do MediaCodec com fallback por arquivo,
  guarda por aparelho e "Modo de vídeo compatível".
- Player: barra que some parada na TV, primeiro BACK só esconde a
  barra na TV, "Ajustando a posição…" na retomada e na troca de
  qualidade HLS, fundo escuro nos botões dos cantos.
- Avisos do app no topo (caem, esperam 4 s e sobem).
- TV: menus compactos (tema, diálogos e cabeçalhos).
- Padrão visual único: o interruptor da TV vale em desktop e celular;
  regras em `docs/PADROES_VISUAIS.md`.

## Fora deste marco (sem bloqueio)

- Volume visual no celular (backlog).
- Feed definitivo e mídia própria/licenciada no lugar do `mux-smoke`.

## Tag

- [ ] `git tag -a v0.2.0` no commit do marco e envio da tag (após
      confirmação).
