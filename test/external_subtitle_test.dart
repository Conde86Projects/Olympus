import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;
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

class _FailingSubtitlePlayer extends NoOpMediaPlayerService {
  @override
  Future<void> addExternalSubtitle(String path) async {
    throw StateError('falhou');
  }
}
