import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player/app/app.dart';
import 'package:player/core/storage/file_store.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/diagnostics_service.dart';
import 'package:player/services/local_addon_service.dart';
import 'package:player/services/media_kit_player_service.dart';
import 'package:player/services/persistent_history_service.dart';
import 'package:player/services/persistent_library_service.dart';
import 'package:player/services/shared_preferences_service.dart';
import 'package:player/services/sources/owned_test_source.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/services/supervised_player_service.dart';
import 'package:player/services/system_volume_service.dart';
import 'package:player/services/tv_info_service.dart';
import 'package:player/services/video_output_guard.dart';
import 'package:player/services/window_service.dart';

/// Ponto de entrada (Fase 2): implementacoes reais com as mesmas interfaces
/// da Fase 1. Nenhuma tela precisou mudar de contrato.
Future<void> main() async {
  StartupGuard? zoneGuard;
  await runZonedGuarded<Future<void>>(
    () => _boot((guard) => zoneGuard = guard),
    (error, stack) {
      final guard = zoneGuard;
      if (guard != null) unawaited(guard.recordError(error, stack));
      debugPrint('Erro de zona no arranque: $error');
    },
  );
}

/// Corpo do arranque, executado DENTRO da zona guardada: o binding e
/// criado aqui para nao disparar "Zone mismatch" (binding fora da
/// zona + runApp dentro).
Future<void> _boot(void Function(StartupGuard) onGuard) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final preferences = SharedPreferencesPreferencesService();
  await preferences.load();

  // Detecção automática de TV (Leanback): com o automático ligado
  // (padrão), o modo TV segue o aparelho. Nunca trava o arranque:
  // fora do Android ou em erro, isTv é false.
  if (preferences.current.tvModeAuto) {
    final isTv = await const TvInfoService().isTv;
    if (isTv != preferences.current.tvMode) {
      await preferences
          .update(preferences.current.copyWith(tvMode: isTv));
    }
  }

  final support = await getApplicationSupportDirectory();
  final store =
      FileLocalStore(Directory('${support.path}${Platform.pathSeparator}player_data'));

  // Guarda de arranque (Fase 5): decide o modo seguro antes de carregar
  // os add-ons. Erros do framework e da zona sao registrados para o
  // diagnostico; o comportamento padrao de exibicao e preservado.
  final guard = StartupGuard(store);
  await guard.beginBoot();
  onGuard(guard);
  FlutterError.onError = (details) {
    unawaited(guard.recordError(details.exception, details.stack));
    FlutterError.presentError(details);
  };

  final library = PersistentLibraryService(store);
  final history = PersistentHistoryService(store);
  // Fonte propria de smoke (Fase 2): so atua no host do feed
  // publicado; o resto do app nao muda.
  final addons = LocalAddonService(
    store,
    adapters: const [OwnedTestSourceAdapter()],
  );
  await Future.wait([library.load(), history.load()]);
  if (!guard.safeMode) {
    await addons.load();
  }

  // Supervisor (spec 26): timeouts, pre-checagem, classificacao e log
  // em volta do motor real.
  // Android (TV e celular): saida direta do decodificador de hardware;
  // desktop segue no padrao do media_kit.
  // Escapes: preferencia "modo de video compativel" e a guarda, que
  // desliga a saida direta sozinha apos quedas nativas seguidas.
  final videoGuard = VideoOutputGuard(store);
  await videoGuard.load();
  WidgetsBinding.instance.addObserver(videoGuard);
  final directOutput = Platform.isAndroid &&
      !preferences.current.compatibleVideoOutput &&
      !videoGuard.autoCompatible;
  final player = SupervisedPlayerService(MediaKitPlayerService(
    videoConfiguration: directOutput
        ? MediaKitPlayerService.androidDirectOutput
        : const VideoControllerConfiguration(),
    directOutputGuard: directOutput ? videoGuard : null,
  ));
  final diagnostics = DiagnosticsService(
    store: store,
    preferences: preferences,
    library: library,
    history: history,
    player: player,
    addons: addons,
    guard: guard,
  );

  // Geometria salva (spec 14.1, 16). Validacao basica contra valores
  // absurdos ou de outro layout de monitores. Respeita a preferencia
  // de restauracao (o salvamento continua, para religar sem perda).
  final saved = preferences.current;
  final restoredBounds =
      saved.restoreWindowGeometry ? _restoredBoundsOrNull(saved) : null;

  // O setup da janela precisa existir antes do runApp para injetar o
  // servico, mas as OPERACOES de janela rodam depois do runApp: aplicar
  // tamanho/posicao antes do primeiro frame deixa a superficie em branco
  // no Windows/Impeller. Fora do desktop injeta o NoOp (o plugin
  // window_manager nao existe no Android: fullscreen/compacto la sao
  // estados de UI, nao de janela).
  final WindowService windows;
  final WindowManagerService? desktopWindows;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final service = WindowManagerService()
      ..onBoundsChanged = (bounds) => preferences.update(
            preferences.current.copyWith(
              windowX: () => bounds.left,
              windowY: () => bounds.top,
              windowWidth: () => bounds.width,
              windowHeight: () => bounds.height,
            ),
          );
    windows = service;
    desktopWindows = service;
  } else {
    windows = NoOpWindowService();
    desktopWindows = null;
  }

  runApp(
    PlayerApp(
      preferencesService: preferences,
      libraryService: library,
      historyService: history,
      playerService: player,
      windowService: windows,
      addonService: addons,
      startupGuard: guard,
      diagnosticsService: diagnostics,
      videoOutputGuard: videoGuard,
      mobilePlatform: Platform.isAndroid || Platform.isIOS,
      systemVolumeService: SystemVolumeService.platform(),
    ),
  );
  // Arranque concluido no primeiro frame: zera as falhas. Se a
  // construcao travar antes, o pendente conta como falha.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(guard.markCleanBoot());
  });

  // Geometria inicial so no desktop (no Android desktopWindows e null).
  await desktopWindows?.applyStartupGeometry(
    title: 'Player',
    alwaysOnTop: preferences.current.alwaysOnTop,
    startInFullscreen: preferences.current.startInFullscreen,
    restoredBounds: restoredBounds,
  );
}

/// Geometria salva valida, ou null para centralizar no tamanho padrao.
Rect? _restoredBoundsOrNull(UserPreferences prefs) {
  final x = prefs.windowX;
  final y = prefs.windowY;
  final w = prefs.windowWidth;
  final h = prefs.windowHeight;
  if (x == null || y == null || w == null || h == null) return null;
  const min = WindowManagerService.minimumSize;
  if (w < min.width || h < min.height || w > 10000 || h > 10000) {
    return null;
  }
  if (x < -2000 || y < -2000 || x > 10000 || y > 10000) return null;
  return Rect.fromLTWH(x, y, w, h);
}
