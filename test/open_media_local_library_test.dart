import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/mobile_chrome_service.dart';
import 'package:player/services/persistent_library_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/window_service.dart';

void main() {
  persistenceGroup();
  testWidgets('arquivo local aberto entra na biblioteca', (tester) async {
    final library = InMemoryLibraryService();
    final preferences = InMemoryPreferencesService();
    preferences.update(preferences.current.copyWith(showOnboarding: false));
    final history = InMemoryHistoryService();
    const player = NoOpMediaPlayerService();
    final guard = StartupGuard(InMemoryLocalStore());
    final addons = LocalAddonService(InMemoryLocalStore());
    final dependencies = AppDependencies(
      preferencesService: preferences,
      libraryService: library,
      historyService: history,
      playerService: player,
      windowService: NoOpWindowService(),
      addonService: addons,
      startupGuard: guard,
      diagnosticsService: DiagnosticsService(
        store: InMemoryLocalStore(),
        preferences: preferences,
        library: library,
        history: history,
        player: player,
        addons: addons,
        guard: guard,
      ),
      mobileChromeService: NoOpMobileChrome(),
    );
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.player) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('player')),
            settings: settings,
          );
        }
        return MaterialPageRoute(
          builder: (_) => OpenMediaScreen(dependencies: dependencies),
        );
      },
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Caminho do arquivo'),
      r'C:\Videos\clip.mp4',
    );
    await tester.tap(find.text('Abrir arquivo'));
    await tester.pumpAndSettle();

    expect(library.items, hasLength(1));
    final MediaItem saved = library.items.single;
    expect(saved.source, r'C:\Videos\clip.mp4');
    expect(saved.sourceType, MediaSourceType.local);
  });
}

void persistenceGroup() {
  test('item local sobrevive a reinicio da biblioteca', () async {
    final store = InMemoryLocalStore();
    final first = PersistentLibraryService(store);
    await first.load();
    await first.upsert(MediaItem(
      id: '1',
      title: 'clip',
      sourceType: MediaSourceType.local,
      source: r'C:\Videos\clip.mp4',
      addedAt: DateTime(2026, 10, 31),
    ));

    final second = PersistentLibraryService(store);
    await second.load();

    expect(second.items, hasLength(1));
    expect(second.items.single.source, r'C:\Videos\clip.mp4');
    expect(second.items.single.sourceType, MediaSourceType.local);
  });
}
