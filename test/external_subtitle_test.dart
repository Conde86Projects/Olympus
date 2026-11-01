import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack, Track, Tracks;
import 'package:player/app/tv_mode.dart';
import 'package:player/features/open_media/pick_subtitle_file.dart';
import 'package:player/features/open_media/tv_file_browser_screen.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_kit_player_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/video_file_listing.dart';
import 'package:player/widgets/player_settings_panel.dart';

Future<NoOpMediaPlayerService> _pumpPanel(
  WidgetTester tester, {
  required Future<String?> Function(BuildContext) pick,
}) async {
  const player = NoOpMediaPlayerService();
  await player.stop();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        child: PlayerSettingsPanel(
          player: player,
          session: player.session,
          initialView: PlayerPanelView.subtitles,
          pickSubtitle: pick,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return player;
}

void main() {
  group('painel de legendas', () {
    testWidgets('abrir arquivo adiciona a faixa e a seleciona', (tester) async {
      final player = await _pumpPanel(
        tester,
        pick: (_) async => r'C:\Filmes\Meu filme.pt.srt',
      );

      await tester.tap(find.text('Abrir arquivo de legenda…'));
      await tester.pumpAndSettle();

      expect(player.session.subtitleTracks.single.label, 'Meu filme.pt.srt');
      expect(player.session.selectedSubtitleId,
          player.session.subtitleTracks.single.id);
      expect(find.text('Meu filme.pt.srt'), findsOneWidget);

      await tester.tap(find.text('Desativadas'));
      await tester.pumpAndSettle();
      expect(player.session.selectedSubtitleId, isNull);
    });

    testWidgets('desistir da escolha nao muda nada', (tester) async {
      final player = await _pumpPanel(tester, pick: (_) async => null);
      // O estado do NoOp e compartilhado entre testes do arquivo.
      final before = player.session.subtitleTracks.length;
      final selected = player.session.selectedSubtitleId;

      await tester.tap(find.text('Abrir arquivo de legenda…'));
      await tester.pumpAndSettle();

      expect(player.session.subtitleTracks, hasLength(before));
      expect(player.session.selectedSubtitleId, selected);
    });

    testWidgets('falha ao carregar avisa sem derrubar o video', (tester) async {
      final player = _FailingSubtitlePlayer();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerSettingsPanel(
            player: player,
            session: player.session,
            initialView: PlayerPanelView.subtitles,
            pickSubtitle: (_) async => '/sdcard/ruim.srt',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir arquivo de legenda…'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível abrir esta legenda.'), findsOneWidget);
      expect(player.session.status, isNot(PlaybackStatus.error));
    });

    testWidgets('arquivo que nao e legenda avisa e nao chega ao player',
        (tester) async {
      final player = _RecordingSubtitlePlayer();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerSettingsPanel(
            player: player,
            session: player.session,
            initialView: PlayerPanelView.subtitles,
            pickSubtitle: (_) async => '/sdcard/Download/foto.jpg',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir arquivo de legenda…'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível abrir esta legenda.'), findsOneWidget);
      expect(player.added, isEmpty);
    });

    test('seletor filtra por extensao, menos no Android', () {
      expect(subtitlePickerFiltersByExtension(TargetPlatform.windows), isTrue);
      expect(subtitlePickerFiltersByExtension(TargetPlatform.android), isFalse);
    });

    testWidgets('a acao so existe no painel de legendas', (tester) async {
      const player = NoOpMediaPlayerService();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerSettingsPanel(
            player: player,
            session: player.session,
            initialView: PlayerPanelView.audio,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Abrir arquivo de legenda…'), findsNothing);
    });
  });

  group('aviso de legenda ao lado nao encontrada', () {
    const aviso = 'Legenda ao lado não encontrada';

    Future<void> pumpAviso(
      WidgetTester tester, {
      required bool localVideo,
      bool tv = false,
      List<MediaTrack> tracks = const [],
    }) async {
      const player = NoOpMediaPlayerService();
      await tester.pumpWidget(TvMode(
        enabled: tv,
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSettingsPanel(
              player: player,
              session: PlaybackSession(subtitleTracks: tracks),
              initialView: PlayerPanelView.subtitles,
              localVideo: localVideo,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('celular, video local, sem legenda: avisa', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpAviso(tester, localVideo: true);
      expect(find.textContaining(aviso), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining('Abrir arquivo de legenda…'), findsWidgets);
    });

    testWidgets('com legenda encontrada, nao avisa', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpAviso(tester, localVideo: true, tracks: const [
        MediaTrack(id: '2', label: 'filme.vtt', isExternal: true),
      ]);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining(aviso), findsNothing);
    });

    testWidgets('video que nao e local, nao avisa', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpAviso(tester, localVideo: false);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining(aviso), findsNothing);
    });

    testWidgets('na TV, nao avisa', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpAviso(tester, localVideo: true, tv: true);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining(aviso), findsNothing);
    });

    testWidgets('no Windows, nao avisa', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpAviso(tester, localVideo: true);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining(aviso), findsNothing);
    });
  });

  test('preferencias so olham as legendas do proprio video', () {
    const embedded = MediaTrack(id: '1', label: 'por', language: 'por');
    const external =
        MediaTrack(id: '2', label: 'externa.srt', isExternal: true);

    expect(
        const PlaybackSession(subtitleTracks: [external]).embeddedSubtitles,
        isEmpty);
    expect(
        const PlaybackSession(subtitleTracks: [embedded, external])
            .embeddedSubtitles,
        [embedded]);
  });

  group('faixa externa selecionada', () {
    final list = [
      const SubtitleTrack('1', 'por', 'pt'),
      const SubtitleTrack('2', 'externa.srt', 'auto'),
    ];

    test('encontra na lista pelo titulo', () {
      final selected = SubtitleTrack.uri('file:///a/externa.srt', title: 'externa.srt');
      expect(MediaKitPlayerService.selectedSubtitleTrackId(selected, list), '2');
    });

    test('faixa comum continua pelo proprio id', () {
      expect(
          MediaKitPlayerService.selectedSubtitleTrackId(list.first, list), '1');
    });

    test('erro de arquivo externo nao conta como erro de reproducao', () {
      expect(
          MediaKitPlayerService.isExternalSubtitleError(
              'Can not open external file /a/ruim.srt.'),
          isTrue);
      expect(
          MediaKitPlayerService.isExternalSubtitleError(
              'tcp: Failed to resolve hostname'),
          isFalse);
    });

    group('faixa no painel', () {
      test('escolha automatica mostra a que o motor ligou', () {
        expect(
            MediaKitPlayerService.panelSubtitleId('auto', engineChoice: '3'),
            '3');
      });

      test('automatica sem nada ligado fica desativada', () {
        expect(
            MediaKitPlayerService.panelSubtitleId('auto', engineChoice: null),
            isNull);
      });

      test('desativada vence o que o motor informou antes', () {
        expect(MediaKitPlayerService.panelSubtitleId('no', engineChoice: '3'),
            isNull);
      });

      test('faixa escolhida fica como esta', () {
        expect(MediaKitPlayerService.panelSubtitleId('2', engineChoice: '3'),
            '2');
      });
    });

    group('fim do video', () {
      test('a lista zerada no fim nao vale: o arquivo segue aberto', () {
        expect(
            MediaKitPlayerService.isEndOfFileReset(const Tracks(),
                completed: true),
            isTrue);
        expect(
            MediaKitPlayerService.isEndOfFileReset(const Track(),
                completed: true),
            isTrue);
      });

      test('lista zerada ao abrir outro arquivo vale', () {
        expect(
            MediaKitPlayerService.isEndOfFileReset(const Tracks(),
                completed: false),
            isFalse);
      });

      test('faixa escolhida depois do fim vale', () {
        expect(
            MediaKitPlayerService.isEndOfFileReset(
                Track(subtitle: list.first),
                completed: true),
            isFalse);
      });
    });

    group('apos falha, volta para a legenda anterior', () {
      test('faixa embutida', () {
        expect(
            MediaKitPlayerService.subtitleToRestore(list.first, list).id, '1');
      });

      test('externa, pela faixa da lista e sem abrir o arquivo de novo', () {
        final restored = MediaKitPlayerService.subtitleToRestore(
            SubtitleTrack.uri('file:///a/externa.srt', title: 'externa.srt'),
            list);
        expect(restored.id, '2');
        expect(restored.uri, isFalse);
      });

      test('desativada continua desativada', () {
        expect(
            MediaKitPlayerService.subtitleToRestore(SubtitleTrack.no(), list).id,
            'no');
      });

      test('externa fora da lista desativa', () {
        expect(
            MediaKitPlayerService.subtitleToRestore(
                SubtitleTrack.uri('file:///a/nova.srt', title: 'nova.srt'),
                list).id,
            'no');
      });
    });

    group('legendas com o mesmo nome em pastas diferentes', () {
      const a = SubtitleTrack('2', 'C:/filmes/a/pt.srt', 'auto');
      const b = SubtitleTrack('3', 'C:/filmes/b/pt.srt', 'auto');
      const unica = SubtitleTrack('4', 'C:/filmes/a/en.srt', 'auto');
      final all = [list.first, a, b, unica];

      test('nome repetido ganha a pasta no rotulo', () {
        expect(MediaKitPlayerService.subtitleLabel(a, all), 'a/pt.srt');
        expect(MediaKitPlayerService.subtitleLabel(b, all), 'b/pt.srt');
      });

      test('caminho do Windows tambem', () {
        const w = SubtitleTrack('5', r'C:\filmes\c\pt.srt', 'auto');
        expect(MediaKitPlayerService.subtitleLabel(w, [...all, w]),
            'c/pt.srt');
      });

      test('nome unico fica so com o nome do arquivo', () {
        expect(MediaKitPlayerService.subtitleLabel(unica, all), 'en.srt');
      });

      test('faixa embutida mantem o titulo', () {
        expect(MediaKitPlayerService.subtitleLabel(list.first, all), 'por');
      });

      test('a marcada e a ligada, mesmo com nomes iguais', () {
        SubtitleTrack ligada(String path) =>
            SubtitleTrack.uri('file:///$path', title: path);
        expect(
            MediaKitPlayerService.selectedSubtitleTrackId(
                ligada('C:/filmes/b/pt.srt'), all),
            '3');
        expect(
            MediaKitPlayerService.selectedSubtitleTrackId(
                ligada('C:/filmes/a/pt.srt'), all),
            '2');
      });
    });

    test('antes de entrar na lista, mantem o endereco', () {
      final selected = SubtitleTrack.uri('file:///a/nova.srt', title: 'nova.srt');
      expect(MediaKitPlayerService.selectedSubtitleTrackId(selected, list),
          'file:///a/nova.srt');
    });
  });

  group('arquivos de legenda', () {
    test('reconhece as extensoes aceitas', () {
      expect(isSubtitleFileName('filme.SRT'), isTrue);
      expect(isSubtitleFileName('filme.vtt'), isTrue);
      expect(isSubtitleFileName('filme.ass'), isTrue);
      expect(isSubtitleFileName('filme.mp4'), isFalse);
      expect(isSubtitleFileName('semextensao'), isFalse);
    });

    test('lista pastas e legendas, sem videos', () async {
      final root = await Directory.systemTemp.createTemp('legendas');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/sub').create();
      await File('${root.path}/b.srt').writeAsString('1');
      await File('${root.path}/a.mp4').writeAsString('1');

      final entries = await listSubtitleFolder(root.path);

      expect(entries.map((e) => e.name), ['sub', 'b.srt']);
    });

    testWidgets('navegador da TV mostra titulo e aviso proprios',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TvFileBrowserScreen(
          roots: const [],
          title: 'Escolher legenda',
          emptyMessage: 'Nenhuma legenda nesta pasta.',
          list: (_) async => const [],
          ensureAccess: () async => true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Escolher legenda'), findsOneWidget);
      expect(find.text('Nenhuma legenda nesta pasta.'), findsOneWidget);
    });
  });
}

class _RecordingSubtitlePlayer extends NoOpMediaPlayerService {
  final List<String> added = [];

  @override
  Future<void> addExternalSubtitle(String path) async => added.add(path);
}

class _FailingSubtitlePlayer extends NoOpMediaPlayerService {
  @override
  Future<void> addExternalSubtitle(String path) async {
    throw StateError('falhou');
  }
}
