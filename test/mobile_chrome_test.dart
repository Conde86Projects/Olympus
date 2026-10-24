import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/constants/app_constants.dart';
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

  bool _controlsVisible = true;
  Duration? _hideIn;

  @override
  bool get controlsVisible => _controlsVisible;

  @override
  bool Function()? autoHideGuard;

  @override
  void Function()? onControlsAutoHidden;

  @override
  void showControls() {
    _hideIn = null;
    if (_controlsVisible) return;
    _controlsVisible = true;
    notifyListeners();
  }

  @override
  void hideControls() {
    _hideIn = null;
    if (!_controlsVisible) return;
    _controlsVisible = false;
    notifyListeners();
  }

  @override
  void toggleControls() {
    if (_controlsVisible && _mayAutoHide()) {
      hideControls();
    } else {
      pokeControls();
    }
  }

  @override
  void pokeControls() {
    _hideIn = AppConstants.controlsAutoHide;
    // Notifica sempre (mesmo ja visivel): espelha o adaptador real.
    _controlsVisible = true;
    notifyListeners();
  }

  @override
  void cancelAutoHide() {
    _hideIn = null;
  }

  bool _mayAutoHide() => autoHideGuard == null || autoHideGuard!();

  /// Avança o relógio determinístico do fake (F2): dispara o auto-hide
  /// sem bombear a tela nem esperar o tempo real.
  void advanceTime(Duration step) {
    final remaining = _hideIn;
    if (remaining == null) return;
    final next = remaining - step;
    if (next <= Duration.zero) {
      _hideIn = null;
      if (_mayAutoHide()) {
        _controlsVisible = false;
        notifyListeners();
        onControlsAutoHidden?.call();
      }
    } else {
      _hideIn = next;
    }
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

      // Sem timer real no fake, os controles seguem visiveis apos a abertura.
      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pumpAndSettle();

      expect(chrome.calls, [true]);
      expect(chrome.isFullscreen, isTrue);

      // Sair tambem passa pelo modulo (poke da alternancia mantem visivel).
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

  group('visibilidade e auto-hide (F2: relógio do fake)', () {
    test('poke mostra e agenda; relógio cheio esconde', () {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      var calls = 0;
      chrome.addListener(() => calls++);

      chrome.hideControls();
      expect(chrome.controlsVisible, isFalse);
      expect(calls, 1);

      chrome.pokeControls();
      expect(chrome.controlsVisible, isTrue);
      expect(calls, 2);

      // Parcial: ainda visível.
      fake.advanceTime(
          AppConstants.controlsAutoHide - const Duration(seconds: 1));
      expect(chrome.controlsVisible, isTrue);

      // Completa o prazo: esconde sem bombear tela alguma.
      fake.advanceTime(const Duration(seconds: 1));
      expect(chrome.controlsVisible, isFalse);
      expect(calls, 3);
    });

    test('guard bloqueando segura o hide no disparo', () {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      var hooked = 0;
      chrome.autoHideGuard = () => false;
      chrome.onControlsAutoHidden = () => hooked++;

      chrome.pokeControls();
      fake.advanceTime(
          AppConstants.controlsAutoHide + const Duration(seconds: 1));

      expect(chrome.controlsVisible, isTrue);
      expect(hooked, 0);
    });

    test('guard liberando esconde e invoca o gancho', () {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      var hooked = 0;
      chrome.autoHideGuard = () => true;
      chrome.onControlsAutoHidden = () => hooked++;

      chrome.pokeControls();
      fake.advanceTime(AppConstants.controlsAutoHide);

      expect(chrome.controlsVisible, isFalse);
      expect(hooked, 1);
    });

    test('toggle alterna pelo guard; show cancela o pendente', () {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      chrome.autoHideGuard = () => true;

      chrome.toggleControls();
      expect(chrome.controlsVisible, isFalse);

      chrome.toggleControls();
      expect(chrome.controlsVisible, isTrue);

      chrome.showControls();
      fake.advanceTime(
          AppConstants.controlsAutoHide + const Duration(seconds: 1));
      expect(chrome.controlsVisible, isTrue);

      chrome.pokeControls();
      chrome.cancelAutoHide();
      fake.advanceTime(
          AppConstants.controlsAutoHide + const Duration(seconds: 1));
      expect(chrome.controlsVisible, isTrue);
    });

    test('repetida sem mudança não renotifica', () {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      var calls = 0;
      chrome.addListener(() => calls++);

      chrome.showControls();
      chrome.hideControls();
      chrome.hideControls();

      expect(chrome.controlsVisible, isFalse);
      expect(calls, 1);
    });

    test('poke visivel rearma e notifica (agenda frame p/ pos-frame)', () {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      var calls = 0;
      chrome.addListener(() => calls++);

      chrome.pokeControls();

      expect(chrome.controlsVisible, isTrue);
      expect(calls, 1);
      fake.advanceTime(AppConstants.controlsAutoHide);
      expect(chrome.controlsVisible, isFalse);
    });
  });

  group('fiacao da visibilidade (F2: tela consome o relogio)', () {
    testWidgets('relogio do fake esconde com um frame so', (tester) async {
      final fake = FakeMobileChrome();
      final MobileChromeService chrome = fake;
      await _openMobilePlayer(tester, fake);

      chrome.pokeControls();
      await tester.pump();
      expect(find.byTooltip('Reproduzir'), findsOneWidget);

      // Sem bombear 4s: o relogio do fake dispara e a tela reage.
      fake.advanceTime(AppConstants.controlsAutoHide);
      await tester.pump();

      expect(chrome.controlsVisible, isFalse);
      expect(find.byTooltip('Reproduzir'), findsNothing);
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
