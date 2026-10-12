# Olympus

Player de mídia minimalista, multiplataforma, em Flutter. Interface em pt-BR,
inspirada nos princípios do Showtime (GNOME) com identidade própria.

Especificação completa em [`docs/`](./docs) — versão 0.1, seções 1–25.

## Estado atual: Fase 2 — player local funcional

- Estrutura de pastas da spec (§20): `app/`, `core/`, `models/`, `services/`,
  `features/`, `widgets/`.
- Contratos definidos antes da implementação (§4.1): `MediaPlayerService`,
  `LibraryService`, `HistoryService`, `PreferencesService`, `LocalStore`,
  `WindowService`.
- Reprodução real via media_kit/libmpv (`MediaKitPlayerService`); a UI usa
  só o contrato — telas e widgets não importam o player.
- Persistência local: preferências em shared_preferences; biblioteca e
  histórico em JSON no application support. Falhas de gravação nunca
  travam a UI (§19).
- Janela real (window_manager): 1280×720 inicial, tela cheia, sempre no
  topo e modo compacto 480×270.
- Seletor nativo de arquivos (file_picker) + campo de caminho/URL.
- `test_assets/` traz vídeos gerados para teste manual (MP4, MKV com duas
  faixas de áudio, 21:9 e legenda `.srt`).

## Estrutura

```text
lib/
├── main.dart            # monta implementações em memória e inicia o app
├── app/                 # app, rotas (§6), tema (§3.3)
├── core/                # erros (§17), constantes, storage, utils, extensions
├── models/              # MediaItem, PlaybackState, Preferences (§5)
├── services/            # contratos + implementações em memória
├── features/            # uma pasta por tela (§4, §20)
└── widgets/             # shell, cards, controles, painel, botões (§20)
test/
└── scaffold_test.dart   # modelos e utils (puros, sem UI)
```

## Pré-requisitos

- Flutter SDK ≥ 3.32 (com Dart ≥ 3.4) instalado e no `PATH`.
- No Windows: Visual Studio com workload "Desktop development with C++" e o
  Windows SDK (exigência do Flutter para apps desktop).

Instalação:

```powershell
# 1. Baixe o SDK em https://docs.flutter.dev/get-started/install/windows
# 2. Extraia (ex.: C:\src\flutter), adicione C:\src\flutter\bin ao PATH
# 3. Valide:
flutter doctor
```

## Executar (após instalar o Flutter)

As pastas de plataforma (`windows/`, `linux/`…) ainda não estão no repo — o
scaffold traz `lib/`, `test/` e `pubspec.yaml`. Gere-as com:

```powershell
cd C:\Users\merli\Projetos\player
flutter create --platforms=windows,linux --project-name player .
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

> `flutter create .` dentro de um projeto existente só adiciona as pastas de
> plataforma que faltam; não apaga `lib/`.

## Decisões pendentes (spec §24)

1. Nome definitivo, logo e cor de destaque.
2. ~~Plataforma desktop prioritária~~ → **Windows** (decidido).
3. ~~Biblioteca de reprodução~~ → **media_kit/libmpv** (Fase 2).
4. ~~Armazenamento local~~ → **shared_preferences + JSON local** (migração
   para SQLite futura só troca o `LocalStore`).
5. Formatos suportados e primeira Smart TV de validação.

## Roteiro

Fase 0 alinhamento → Fase 1 protótipo navegável → Fase 2 player local →
**Fase 3 refinamento desktop (atual)** → Fase 4 preparação TV →
Fase 5 fontes autorizadas.

Fase 2 verificada com teste de integração no Windows real
(`flutter test -d windows integration_test/playback_test.dart`): MP4,
pausa, 2 faixas de áudio, legenda externa, arquivo incompatível e 21:9.
Fase 3: geometria da janela persistida (tamanho/posição restaurados),
largura máxima de conteúdo para ultrawide, modo cinema (botão, C, Esc),
atalhos I/S/A abrindo o painel direto na subview, ações de fim de vídeo
(rever, favoritar, próximo, fechar) e botão de tela cheia refletindo o
estado. Preferências honradas (autoplay, retomar, lembrar posição,
volume inicial, idiomas preferidos, animações, restaurar geometria),
Configurações completa (§16) com seção de atalhos, apresentação inicial
no primeiro uso (§7), próximo item automático (§11) e ações de erro
(editar link, localizar arquivo, remover da biblioteca — §17).

Limitação conhecida: estilo de legenda (tamanho, cor, fundo, posição,
§16) não está disponível — o media_kit não expõe essas propriedades do
mpv pela API Dart. Registrado como backlog técnico em
[`docs/BACKLOG.md`](./docs/BACKLOG.md), sem bloquear a entrega.
