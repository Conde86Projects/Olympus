# Checklist de release — v0.2.1 (feed definitivo)

Versão: `0.2.1+16` (versionCode 16, versionName 0.2.1).
Base: `v0.2.0` (`4259d48`) preservada; a tag `v0.2.1` é criada só
depois destes gates.

## Gates

- [x] `flutter analyze`: sem problemas.
- [x] `flutter test`: 653/653.
- [x] `pubspec.yaml` e `AppConstants.appVersion` coerentes (0.2.1).
- [x] Host temporário `*.us4.manus.computer` removido do adaptador
      e dos testes (`lib/services/sources/owned_test_source.dart`).
- [x] Feed definitivo: `https://conde86projects.github.io/olympus-catalog/feed.json`
      (somente Big Buck Bunny, CC-BY 3.0).
- [x] `feed-smoke.json` separado, só para testes técnicos de HLS.

## APK release final

- Arquivo: `build/app/outputs/flutter-apk/app-release.apk`
- Tamanho: 97.823.960 bytes
- SHA-256: `d2d6749d44bbcaea35c027a4e091cca9428d509b60f8fafb3bbc3673aa0a27c0`

## Resultados por plataforma

- [x] **Windows** (build 0.2.1+12, 19/10): prévia, ativação,
      catálogo, miniatura, MP4, seek, retomada, histórico, 97%,
      "Ver de novo", fechar pelo X, erro controlado. Detalhes em
      `docs/RESULTADOS_TESTES_0.2.1.md`.
- [x] **TCL** (build 0.2.1, validado pelo usuário com o controle):
      feed definitivo funcionando, incluindo seek, retomada e "Ver de novo".
- [x] **Celular** (build 0.2.1, validado pelo usuário): roteiro
      completo.

## Correções visuais incluídas no fechamento

- Cancelar só na abertura, não no buffering do seek.
- Folha do item cabe em tela deitada (TV, desktop).
- Foco visível nos ícones da TV.
- Estado Ativo em verde; Inativo e Erro em vermelho.
- Foco do cartão de mídia cobre o cartão inteiro.

## Fora desta versão

- Controle visual de volume no celular (melhoria futura).
- Sintel e Tears of Steel (dependem de hospedagem).
