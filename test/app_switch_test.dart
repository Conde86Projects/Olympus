import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

/// Padrão visual único (19/10/2026): o interruptor aprovado na TV
/// (trilho fino, dedão azul quando ligado, cinza quando desligado)
/// vale também no desktop e no celular.
Future<void> _openSettings(WidgetTester tester,
    {required bool tv, required bool mobile, required Size size}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final prefs = InMemoryPreferencesService();
  await prefs.update(
      prefs.current.copyWith(showOnboarding: false, tvMode: tv));
  final library = InMemoryLibraryService();
  final history = InMemoryHistoryService();
  const player = NoOpMediaPlayerService();
  final guard = StartupGuard(InMemoryLocalStore());
  final addons = LocalAddonService(InMemoryLocalStore());
  await tester.pumpWidget(PlayerApp(
    preferencesService: prefs,
    libraryService: library,
    historyService: history,
    playerService: player,
    windowService: NoOpWindowService(),
    addonService: addons,
    startupGuard: guard,
    mobilePlatform: mobile,
    diagnosticsService: DiagnosticsService(
      store: InMemoryLocalStore(),
      preferences: prefs,
      library: library,
      history: history,
      player: player,
      addons: addons,
      guard: guard,
    ),
  ));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).pushNamed(AppRoutes.settings);
  await tester.pumpAndSettle();
}

void main() {
  for (final c in const [
    (name: 'desktop', tv: false, mobile: false, size: Size(1280, 720)),
    (name: 'celular', tv: false, mobile: true, size: Size(390, 844)),
    (name: 'TV', tv: true, mobile: false, size: Size(960, 540)),
  ]) {
    testWidgets('switch padrao do app no ${c.name}', (tester) async {
      await _openSettings(tester, tv: c.tv, mobile: c.mobile, size: c.size);
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);
      for (final element in switches.evaluate()) {
        final theme = Theme.of(element);
        // Desenho classico (nao o M3 de 52x32) com as cores do padrao.
        expect(theme.useMaterial3, isFalse);
        final thumb = theme.switchTheme.thumbColor!;
        expect(thumb.resolve({WidgetState.selected}), PlayerTheme.accent);
        expect(thumb.resolve(<WidgetState>{}), PlayerTheme.secondaryText);
      }
      // O texto da linha com interruptor segue igual ao das demais
      // linhas (sem o negrito do modo classico).
      TextStyle effective(String text) {
        final rich = tester.widget<RichText>(find
            .descendant(of: find.text(text), matching: find.byType(RichText))
            .first);
        return rich.text.style!;
      }
      final withSwitch = effective('Modo TV');
      final plain = effective('Velocidade padrão');
      expect(withSwitch.fontSize, plain.fontSize);
      expect(withSwitch.fontWeight, plain.fontWeight);
    });
  }
}
