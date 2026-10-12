import 'dart:io';

import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/services/history_service.dart';
import 'package:player/services/library_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/preferences_service.dart';
import 'package:player/services/startup_guard.dart';

/// Foto do estado do app para a tela de diagnostico. A [lastErrorMessage]
/// aparece SOMENTE na tela (dado local do proprio usuario): o relatorio
/// exportado leva so o horario, nunca a mensagem (spec 6.1: sem caminhos,
/// URLs ou credenciais).
class DiagnosticsReport {
  const DiagnosticsReport({
    required this.appVersion,
    required this.platform,
    required this.playerLabel,
    required this.storageOk,
    required this.libraryCount,
    required this.favoritesCount,
    required this.historyCount,
    required this.addonsActive,
    required this.addonsInactive,
    required this.addonsError,
    required this.reposCount,
    required this.safeMode,
    required this.safeModeLabel,
    required this.lastErrorAt,
    required this.lastErrorMessage,
    required this.lastChangeName,
  });

  final String appVersion;
  final String platform;
  final String playerLabel;
  final bool storageOk;
  final int libraryCount;
  final int favoritesCount;
  final int historyCount;
  final int addonsActive;
  final int addonsInactive;
  final int addonsError;
  final int reposCount;
  final bool safeMode;
  final String safeModeLabel;
  final String? lastErrorAt;
  final String? lastErrorMessage;
  final String? lastChangeName;

  int get addonsTotal => addonsActive + addonsInactive + addonsError;
}

/// Diagnostico e recuperacao (spec 6.1): coleta estado dos componentes
/// e executa as acoes de reparo. Nenhuma acao toca arquivos de midia.
class DiagnosticsService {
  DiagnosticsService({
    required LocalStore store,
    required PreferencesService preferences,
    required LibraryService library,
    required HistoryService history,
    required MediaPlayerService player,
    required AddonService addons,
    required StartupGuard guard,
  })  : _store = store,
        _preferences = preferences,
        _library = library,
        _history = history,
        _player = player,
        _addons = addons,
        _guard = guard;

  final LocalStore _store;
  final PreferencesService _preferences;
  final LibraryService _library;
  final HistoryService _history;
  final MediaPlayerService _player;
  final AddonService _addons;
  final StartupGuard _guard;

  /// Coleta o estado atual. A sonda de armazenamento escreve, le e
  /// remove uma chave temporaria: falha vira `storageOk: false`.
  Future<DiagnosticsReport> collect() async {
    var storageOk = false;
    try {
      const probe = '__diagnostics_probe__';
      await _store.write(probe, const {'ok': true});
      final back = await _store.read(probe);
      storageOk = back?['ok'] == true;
      await _store.remove(probe);
    } catch (_) {
      storageOk = false;
    }

    var active = 0, inactive = 0, errors = 0;
    for (final info in _addons.addons) {
      switch (info.state) {
        case AddonState.active:
          active++;
        case AddonState.error:
          errors++;
        case AddonState.inactive:
          inactive++;
      }
    }

    final lastError = _guard.lastError;
    // A coleta nunca lanca: diagnostico quebrado nao diagnostica nada.
    String? lastChangeName;
    try {
      lastChangeName = (await _guard.readLastChange())?.name;
    } catch (_) {
      lastChangeName = null;
    }
    return DiagnosticsReport(
      appVersion: AppConstants.appVersion,
      platform: Platform.operatingSystem,
      playerLabel: _playerLabel(_player.session.status),
      storageOk: storageOk,
      libraryCount: _library.items.length,
      favoritesCount: _library.favorites.length,
      historyCount: _history.entries.length,
      addonsActive: active,
      addonsInactive: inactive,
      addonsError: errors,
      reposCount: _addons.repositories.length,
      safeMode: _guard.safeMode,
      safeModeLabel: switch (_guard.safeModeReason) {
        SafeModeReason.manual => 'sim (manual)',
        SafeModeReason.crashes =>
          'sim (${_guard.consecutiveFailures} falhas no arranque)',
        null => 'não',
      },
      lastErrorAt: lastError?['at'] as String?,
      lastErrorMessage: lastError?['message'] as String?,
      lastChangeName: lastChangeName,
    );
  }

  /// Restaura os padroes SEM tocar biblioteca, historico, midias ou
  /// add-ons. Nao reexibe a apresentacao na sessao atual.
  Future<void> restoreDefaults() async {
    await _preferences.update(
      const UserPreferences(showOnboarding: false),
    );
  }

  /// Limpa registros efemeros (o app nao acumula cache de midia nesta
  /// versao; ver [StartupGuard.clearEphemeral]).
  Future<void> clearEphemeral() => _guard.clearEphemeral();

  /// Apaga TODOS os dados do app (prefs, biblioteca, historico, add-ons,
  /// repositorios, estado de recuperacao). Midias nunca sao tocadas. O
  /// proximo arranque volta a apresentacao inicial.
  Future<void> clearAppData() async {
    await _library.clear();
    await _history.clear();
    await _addons.clearAllData();
    await _guard.clearRecoveryData();
    await _preferences.update(const UserPreferences());
  }

  /// Texto para exportacao (area de transferencia). So contagens e
  /// estados: nenhum caminho, URL, mensagem de erro ou credencial.
  String buildReport(DiagnosticsReport report) {
    return [
      'Relatório de diagnóstico — Player ${report.appVersion}',
      'Plataforma: ${report.platform}',
      'Player: ${report.playerLabel}',
      'Armazenamento local: ${report.storageOk ? 'ok' : 'FALHA'}',
      'Modo seguro: ${report.safeModeLabel}',
      'Biblioteca: ${report.libraryCount} vídeos, '
          '${report.favoritesCount} favoritos',
      'Histórico: ${report.historyCount} entradas',
      'Add-ons: ${report.addonsTotal} instalados '
          '(${report.addonsActive} ativos, '
          '${report.addonsInactive} inativos, '
          '${report.addonsError} em erro)',
      'Repositórios: ${report.reposCount} cadastrados',
      'Último erro: ${report.lastErrorAt ?? 'nenhum registrado'}',
      'Última alteração de add-on: ${report.lastChangeName ?? 'nenhuma'}',
    ].join('\n');
  }

  /// Instrucoes de reinstalacao. Genericas de proposito: sem loja ou
  /// instalador definidos, o procedimento e o mesmo (limpar os dados
  /// do app e abrir de novo); o texto nomeia a plataforma atual.
  String reinstallInstructions() {
    final os = switch (Platform.operatingSystem) {
      'windows' => 'no Windows',
      'linux' => 'no Linux',
      'macos' => 'no macOS',
      'android' => 'no Android',
      _ => 'neste sistema',
    };
    return 'Para reinstalar $os: feche o app, use "Limpar dados do app" '
        'acima (ou apague a pasta de dados do aplicativo) e abra '
        'novamente. Seus vídeos não são afetados.';
  }

  static String _playerLabel(PlaybackStatus status) => switch (status) {
        PlaybackStatus.idle => 'ocioso',
        PlaybackStatus.loading => 'carregando',
        PlaybackStatus.ready => 'pronto',
        PlaybackStatus.playing => 'reproduzindo',
        PlaybackStatus.paused => 'pausado',
        PlaybackStatus.buffering => 'em buffer',
        PlaybackStatus.completed => 'concluído',
        PlaybackStatus.error => 'em erro',
      };
}
