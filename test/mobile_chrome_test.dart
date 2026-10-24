import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/mobile_chrome_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

class FakeMobileChrome extends MobileChromeService {
  bool _fullscreen = false;
  final List<bool> calls = [];

  @override
  bool get isFullscreen => _fullscreen;

  @override
  Future<void> setFullscreen(bool enabled) async {
    calls.add(enabled);
    if (_fullscreen == enabled) return;
    _fullscreen = enabled;
    notifyListeners();
  }
}

void main() {
  group('MobileChrome (passo 1: seam + fake)', () {
    test('entra e sai da cheia notificando uma vez por mudanca', () async {
      final chrome = FakeMobileChrome();
      var calls = 0;
      chrome.addListener(() => calls++);

      expect(chrome.isFullscreen, isFalse);

      await chrome.setFullscreen(true);
      expect(chrome.isFullscreen, isTrue);
      expect(calls, 1);

      await chrome.setFullscreen(false);
      expect(chrome.isFullscreen, isFalse);
      expect(calls, 2);
    });

    test('chamada repetida nao renotifica', () async {
      final chrome = FakeMobileChrome();
      var calls = 0;
      chrome.addListener(() => calls++);

      await chrome.setFullscreen(true);
      await chrome.setFullscreen(true);

      expect(chrome.isFullscreen, isTrue);
      expect(chrome.calls, [true, true]);
      expect(calls, 1);
    });
  });

  group('fiacao da tela cheia no mobile (passo 2: tela consome o seam)', () {
    testWidgets('botao Tela cheia delega ao MobileChrome injetado',
        (tester) async {
      final chrome = FakeMobileChrome();
      await _openMobilePlayer(tester, chrome);

      // Reexibe os controles (auto-ocultos após a abertura).
      await tester.tapAt(const Offset(400, 150));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pumpAndSettle();

      expect(chrome.calls, [true]);
      expect(chrome.isFullscreen, isTrue);

      // Sair também passa pelo módulo.
      await tester.tapAt(const Offset(400, 150));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sair da tela cheia'));
      await tester.pumpAndSettle();

      expect(chrome.calls, [true, false]);
      expect(chrome.isFullscreen, isFalse);

      // Direção módulo→tela: mudança externa reconstrói (assinatura).
      await chrome.setFullscreen(true);
      await tester.pump();

      expect(chrome.isFullscreen, isTrue);
      expect(find.byTooltip('Sair da tela cheia', skipOffstage: false),
          findsOneWidget);

      // Sair do player em cheia restaura pelo módulo (dispose).
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();

      expect(chrome.calls, [true, false, true, false]);
      expect(chrome.isFullscreen, isFalse);
    });
  });
}

class _ChromeHarness {
  _ChromeHarness({required this.chrome})
      : preferences = InMemoryPreferencesService(),
        library = InMemoryLibraryService(),
        history = InMemoryHistoryService(),
        player = const NoOpMediaPlayerService(),
        windows = NoOpWindowService(),
        guard = StartupGuard(InMemoryLocalStore()),
        addons = LocalAddonService(InMemoryLocalStore()) {
    preferences.update(preferences.current.copyWith(showOnboarding: false));
  }

  final MobileChromeService chrome;
  final InMemoryPreferencesService preferences;
  final InMemoryLibraryService library;
  final InMemoryHistoryService history;
  final NoOpMediaPlayerService player;
  final NoOpWindowService windows;
  final LocalAddonService addons;
  final StartupGuard guard;

  DiagnosticsService get diagnostics => DiagnosticsService(
        store: InMemoryLocalStore(),
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      );

  Widget get app => PlayerApp(
        preferencesService: preferences,
        libraryService: library,
        historyService: history,
        playerService: player,
        windowService: windows,
        addonService: addons,
        startupGuard: guard,
        diagnosticsService: diagnostics,
        mobilePlatform: true,
        mobileChromeService: chrome,
      );
}

Future<_ChromeHarness> _openMobilePlayer(
    WidgetTester tester, MobileChromeService chrome) async {
  final harness = _ChromeHarness(chrome: chrome);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  final item = MediaItem(
    id: 'chrome',
    title: 'Vídeo chrome',
    sourceType: MediaSourceType.url,
    source: 'https://exemplo.com/chrome.mp4',
    duration: const Duration(minutes: 10),
    addedAt: DateTime(2026, 1, 1),
  );
  await harness.library.upsert(item);
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.player, arguments: item);
  await tester.pumpAndSettle();
  return harness;
}
