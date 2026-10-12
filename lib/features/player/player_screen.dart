import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_permission_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/thumbnail_service.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_controls.dart';
import 'package:player/widgets/player_settings_panel.dart';
import 'package:player/widgets/tv_player_controls.dart';

/// Tela do player (spec 11, 12): video ao centro, controles flutuantes com
/// auto-ocultar, atalhos de teclado e hierarquia do botao voltar (spec 18).
/// Aplica as preferencias de reproducao na abertura (spec 16), avanca para
/// o proximo item (spec 11) e oferece acoes de erro por tipo de midia
/// (spec 17). A tela nao conhece a biblioteca de video: tudo passa pelo
/// [MediaPlayerService].
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.dependencies,
    required this.item,
  });

  final AppDependencies dependencies;
  final MediaItem item;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  StreamSubscription<PlaybackSession>? _subscription;
  PlaybackSession _session = const PlaybackSession();
  Timer? _hideTimer;
  Timer? _resumeTimer;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _compact = false;
  bool _cinema = false;
  bool _panelOpen = false;
  bool _allowPop = false;

  /// Item em reproducao. Comeca como o da rota e muda ao localizar o
  /// arquivo novamente (spec 17.5), sem sair da tela.
  late MediaItem _currentItem;

  /// Item como aberto (URL padrao) + rendicao atual da fonte (5C).
  /// A troca so muda a fonte; o id segue o mesmo (historico unico).
  late MediaItem _baseItem;

  /// Rendicao atual da fonte (null = URL padrao). Notificador para que
  /// o painel de configuracoes — rota separada — atualize o rotulo
  /// "Qualidade" ao vivo sem precisar reabrir.
  late final ValueNotifier<String?> _sourceQuality;

  /// Faixas preferidas ja aplicadas nesta abertura. Audio e legenda
  /// chegam em momentos distintos no inicio da midia: um flag so
  /// perderia a segunda leva.
  bool _appliedAudio = false;
  bool _appliedSubtitles = false;

  /// Ancora do botao de configuracoes para os atalhos I/S/A (spec 3.5).
  final _settingsKey = GlobalKey();

  /// Foco da tela: retomado ao trocar o modo de exibicao, para que o
  /// teclado continue funcionando quando a barra some (spec 12).
  final _screenFocus = FocusNode(debugLabel: 'player');

  /// Escopo da barra de controles: no modo TV, foco aqui dentro segura
  /// o auto-hide (spec 12.2).
  final _controlsScope = FocusScopeNode(debugLabel: 'controls');

  /// Escopo dos cantos: alvo de quem sobe do card (a faixa do
  /// slider, de largura total, capturaria o raio para cima).
  final _cornerScope = FocusScopeNode(debugLabel: 'corners');
  /// No do botao primario do overlay (erro/concluido, F2 Fase 4b):
  /// autofocus sozinho nao transfere o foco quando ele esta no no
  /// da tela; este no e reivindicado explicito pos-frame.
  final _overlayPrimaryFocus = FocusNode(debugLabel: 'overlay-primary');
  bool _wasOverlayUp = false;
  /// Ultimo controle focado antes do hide (F5, Fase 4b): o poke
  /// restaura nele, nao no primeiro da ordem (cantos).
  FocusNode? _lastControlFocus;

  /// Politica direcional do player (Fase 4). Instancia estavel com os
  /// escopos acima; instalada no [FocusTraversalGroup] da tela.
  late final _PlayerTraversalPolicy _traversalPolicy =
      _PlayerTraversalPolicy(
        controlsScope: _controlsScope,
        cornerScope: _cornerScope,
      );

  bool get _tvMode =>
      widget.dependencies.preferencesService.current.tvMode;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _baseItem = widget.item;
    _sourceQuality = ValueNotifier<String?>(null);
    // Ao sair da barra no modo TV, rearma o auto-hide (e so).
    _controlsScope.addListener(() {
      if (mounted &&
          _controlsVisible &&
          _tvMode &&
          !_panelOpen &&
          !_controlsScope.hasFocus) {
        _scheduleHide();
      }
    });
    final player = widget.dependencies.playerService;
    _subscription = player.sessionStream.listen((session) {
      if (!mounted) return;
      final was = _session.status;
      setState(() => _session = session);
      if (!_appliedAudio && session.audioTracks.isNotEmpty) {
        _appliedAudio = true;
        _applyPreferredAudio(session);
      }
      if (!_appliedSubtitles && session.subtitleTracks.isNotEmpty) {
        _appliedSubtitles = true;
        _applyPreferredSubtitles(session);
      }
      if (session.status == PlaybackStatus.completed &&
          was != PlaybackStatus.completed) {
        _maybeAutoAdvance();
      }
      if ((was == PlaybackStatus.error || was == PlaybackStatus.completed) &&
          session.status != PlaybackStatus.error &&
          session.status != PlaybackStatus.completed) {
        // Overlay fechou pela stream (retry/replay): reexibe e devolve
        // o foco, que morreu com os botoes do overlay (F2, Fase 4b).
        _poke();
        _restoreFocusIfLost();
      }
    });
    _open();
    // F2 (Fase 4b): o no da tela ancora o foco (hide) mas nunca e
    // destino de travessia: com o rect tela-cheia ele capturava as
    // setas (inclusive saindo dos overlays) e nao soltava mais. O
    // requestFocus explicito continua funcionando.
    _screenFocus.skipTraversal = true;
    // F1 (Fase 4b): o D-pad com a barra oculta nao pode depender do
    // ShortcutManager - no aparelho os bindings nao disparavam mesmo
    // com o foco dentro da subarvore. Handler global, independente
    // de foco; consome a tecla para executar uma unica vez.
    HardwareKeyboard.instance.addHandler(_handleHiddenKeys);
  }

  Future<void> _open() async {
    // F8-runtime (Fase 4b): arquivo local pede acesso de midia antes de
    // abrir (dialogo do sistema no Android). Negar nao trava: o open
    // falha e o overlay F9 explica que o problema e da fonte.
    if (_currentItem.sourceType == MediaSourceType.local) {
      await const MediaPermissionService().ensureAccess();
      // Backfill de miniatura (spec 15.1): itens antigos ganham thumb
      // ao reproduzir. Depois da permissao: o retriever le o arquivo.
      unawaited(ThumbnailService.backfill(
        widget.dependencies.libraryService,
        _currentItem,
      ));
    }
    final player = widget.dependencies.playerService;
    _appliedAudio = false;
    _appliedSubtitles = false;
    await player.open(_currentItem);
    // Aplica preferencias de reproducao apos abrir (spec 16).
    final prefs = widget.dependencies.preferencesService.current;
    await player.setSpeed(prefs.defaultSpeed);
    await player.setVolume(prefs.initialVolume);
    // As faixas costumam chegar depois: vale o que existir agora e o
    // restante e aplicado pelo listener quando chegar.
    await _applyPreferredAudio(player.session);
    await _applyPreferredSubtitles(player.session);
    final resume = _currentItem.lastPosition;
    if (prefs.resumeAutomatically &&
        resume != null &&
        resume > Duration.zero) {
      // TV-RESUME (TV fisica, mpv frio): seek disparado antes de o mpv
      // conhecer o arquivo e descartado em silencio -- a retomada so
      // vale depois da duracao chegar (com timeout para nao travar
      // arquivo quebrado: o erro segue o fluxo normal).
      await _waitForDuration(player, const Duration(seconds: 5));
      if (!mounted) return;
      await player.seek(resume);
      _verifyResume(player, resume);
    }
    if (prefs.autoplay) {
      await player.play();
    }
    if (mounted) {
      setState(() => _session = player.session);
      // Reexibe (retry apos erro) e rearma; sem isso o retry voltava
      // tocando com a barra oculta e o foco orfao (F2, Fase 4b).
      _poke();
      // Tentar de novo fecha o overlay modal: o foco morreu com ele.
      _restoreFocusIfLost();
    }
  }

  /// Espera a duracao chegar (mpv com arquivo conhecido) antes do seek
  /// de retomada. Retorna de imediato se ja houver duracao; timeout
  /// silencioso para nao travar arquivo quebrado.
  Future<void> _waitForDuration(MediaPlayerService player, Duration timeout) async {
    // Le o motor, nao o espelho do widget: o evento de duracao pode ter
    // chegado entre o open e esta linha (o listener atualiza depois).
    if (player.session.duration != null) return;
    try {
      await player.sessionStream
          .firstWhere((session) => session.duration != null)
          .timeout(timeout);
    } on TimeoutException {
      // Segue sem duracao: o erro de abertura aparece pelo fluxo normal.
    }
  }

  /// TV-RESUME: em mpv frio o seek de retomada pode ser descartado em
  /// silencio durante a inicializacao do decodificador. Re-dispara em
  /// loop limitado quando ha prova FORTE de vida: 3 s de quadros
  /// decodificados avancando, ou pausado com duracao. As tentativas
  /// sao ESPACADAS (1 a cada 4 s, no maximo 5 em ~20 s). Timer
  /// periodico cancelavel (dispose/nova abertura). Aborta perto
  /// do fim, no erro, se o usuario buscou por conta propria,
  /// ou com a tela fora.
  void _verifyResume(MediaPlayerService player, Duration target) {
    _resumeTimer?.cancel();
    var prev = player.session.position;
    var retries = 0;
    var justRetried = false;
    var busy = false;
    DateTime? lastRetry;
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    void stop() {
      _resumeTimer?.cancel();
      _resumeTimer = null;
    }

    _resumeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || retries >= 5 || !DateTime.now().isBefore(deadline)) {
        stop();
        return;
      }
      if (busy) return;
      busy = true;
      Future(() async {
        try {
          final s = player.session;
          if (s.errorMessage != null) {
            stop();
            return;
          }
          final pos = s.position;
          final dur = s.duration;
          if (dur != null && pos >= dur - const Duration(seconds: 5)) {
            stop();
            return;
          }
          if ((pos - target).abs() <= const Duration(seconds: 4)) {
            stop();
            return;
          }
          if (!justRetried && (pos - prev).abs() > const Duration(seconds: 6)) {
            stop();
            return;
          }
          justRetried = false;
          final hot = pos >= const Duration(seconds: 3) && pos > prev;
          final pausedReady =
              s.status == PlaybackStatus.paused && dur != null;
          prev = pos;
          if (!hot && !pausedReady) return;
          // Espaca as tentativas: sem isso as 5 queimavam nos primeiros
          // segundos e o loop saia antes de a janela fria fechar na TV
          // lenta (retomada caia em 0:0x). 5 x 4 s cobre ~20 s.
          final now = DateTime.now();
          final last = lastRetry;
          if (last != null &&
              now.difference(last) < const Duration(seconds: 4)) {
            return;
          }
          retries++;
          lastRetry = now;
          justRetried = true;
          await player.seek(target);
        } finally {
          busy = false;
        }
      });
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHiddenKeys);
    _hideTimer?.cancel();
    _resumeTimer?.cancel();
    _subscription?.cancel();
    _screenFocus.dispose();
    _sourceQuality.dispose();
    _controlsScope.dispose();
    _cornerScope.dispose();
    _overlayPrimaryFocus.dispose();
    super.dispose();
  }

  /// Overlay modal de erro ou fim de video no ar (spec 11, 17).
  bool get _overlayUp =>
      _session.status == PlaybackStatus.error ||
      _session.status == PlaybackStatus.completed;

  @override
  Widget build(BuildContext context) {
    final next = _nextItem;
    // Margem segura anti-overscan na TV (spec 27.5); 16 no desktop.
    final edge =
        TvLayout.isTv(context) ? TvLayout.safeMarginOf(context) : 16.0;
    // Toda saida pela navegacao (X dos cantos, gesto, voltar do
    // sistema/TV, Q) passa por aqui: salva a sessao antes de fechar
    // (spec 11, 19). O Esc passa pelo _onBack e cai aqui no fim.
    // F2 (Fase 4b): overlay modal abriu. O autofocus sozinho nao
    // transfere o foco quando ele esta no no da tela (barra oculta
    // antes do fim/erro); reivindica o no primario explicito.
    if (_overlayUp && !_wasOverlayUp) {
      _wasOverlayUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayUp) _overlayPrimaryFocus.requestFocus();
      });
    } else if (!_overlayUp) {
      _wasOverlayUp = false;
    }
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Mesma hierarquia do _onBack (spec 18): dialogo e tratado
        // pela propria rota; tela cheia e cinema saem sem fechar.
        if (_fullscreen) {
          await _toggleFullscreen();
          return;
        }
        if (_cinema) {
          _toggleCinema();
          return;
        }
        await _saveSession();
        if (!context.mounted) return;
        setState(() => _allowPop = true);
        Navigator.of(context).pop();
      },
      child: CallbackShortcuts(
        bindings: _shortcuts(),
        // Sem autofocus aqui de proposito (Fase 4): o foco inicial
        // cai no primeiro controle (Reproduzir), de onde o D-pad
        // navega; do no raiz as setas nao sairiam do lugar.
        // Overlays modais tem autofocus proprio no botao primario.
        child: Focus(
          focusNode: _screenFocus,
          child: FocusTraversalGroup(
            policy: _traversalPolicy,
            child: Scaffold(
              backgroundColor: Colors.black,
            body: Theme(
              data: PlayerTheme.playerSurface(Theme.of(context)),
              child: MouseRegion(
                onHover: (_) => _poke(),
                child: GestureDetector(
                  onTap: _poke,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _VideoArea(
                        player: widget.dependencies.playerService,
                        session: _session,
                        isLocal:
                            _currentItem.sourceType == MediaSourceType.local,
                        onRetry: _open,
                        onCancel: () => widget.dependencies.playerService
                            .stop(),
                        onRelocate: _relocate,
                        onRemoveFromLibrary: _removeFromLibrary,
                        onEditLink: _editLink,
                        onReplay: _replay,
                        isFavorite: _isFavorite,
                        onToggleFavorite: _toggleFavorite,
                        nextTitle: next?.title,
                        onPlayNext:
                            next == null ? null : () => _playNext(next),
                        onClose: () =>
                            Navigator.of(context).maybePop(),
                        primaryFocus: _overlayPrimaryFocus,
                      ),
                      // Cantos flutuantes (Showtime): tela cheia a esquerda;
                      // cinema, compacto, favorito e fechar a direita. Mesma
                      // regra da AppBar antiga (escopo proprio, politica
                      // direcional inalterada, visiveis sobre o overlay
                      // para a fuga para cima e a saida), mas somem com
                      // os controles e no cinema. Na tela cheia aparecem
                      // no poke: a saida pelo botao mora aqui.
                      Positioned(
                        left: edge,
                        right: edge,
                        top: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Visibility(
                            visible: _controlsVisible && !_cinema,
                            maintainState: true,
                            maintainAnimation: true,
                            child: ExcludeFocus(
                              excluding:
                                  !_controlsVisible || _cinema,
                              child: FocusScope(
                                node: _cornerScope,
                                child: Row(
                                  children: [
                                    RoundPlayerButton(
                                      tooltip: _fullscreen
                                          ? 'Sair da tela cheia'
                                          : 'Tela cheia',
                                      icon: _fullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      onPressed: _toggleFullscreen,
                                    ),
                                    const Spacer(),
                                    RoundPlayerButton(
                                      tooltip: 'Modo cinema',
                                      icon: Icons.theaters_outlined,
                                      onPressed: _toggleCinema,
                                    ),
                                    RoundPlayerButton(
                                      tooltip: _compact
                                          ? 'Sair do modo compacto'
                                          : 'Modo compacto',
                                      icon: Icons
                                          .picture_in_picture_alt_outlined,
                                      onPressed: _toggleCompact,
                                    ),
                                    RoundPlayerButton(
                                      tooltip: _isFavorite
                                          ? 'Remover dos favoritos'
                                          : 'Adicionar aos favoritos',
                                      icon: _isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_outline,
                                      onPressed: _toggleFavorite,
                                    ),
                                    RoundPlayerButton(
                                      tooltip: 'Fechar',
                                      icon: Icons.close,
                                      onPressed: () => Navigator.of(context)
                                          .maybePop(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // O card nunca desmonta (Fase 4): so oculta com estado.
                      // Desmontar mataria o foco do controle atual e as
                      // setas nao chegariam aos bindings (D-pad morto);
                      // oculto, o foco sobrevive, setas buscam e o OK
                      // continua alternando play/pause.
                      Positioned(
                        left: edge,
                        right: edge,
                        bottom: edge,
                        child: SafeArea(
                          top: false,
                          child: Visibility(
                            visible: _controlsVisible && !_overlayUp,
                            maintainState: true,
                            maintainAnimation: true,
                            // F2 (Fase 4b): oculto, o card sai da travessia - sem
                            // isso, com overlay no ar (onde o handler global se
                            // cala), as setas alcancavam botoes invisiveis.
                            child: ExcludeFocus(
                              excluding: !_controlsVisible || _overlayUp,
                              child: FocusScope(
                              node: _controlsScope,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxWidth: 880),
                                  child: _tvMode
                                      ? TvPlayerControls(
                                          player: widget.dependencies
                                              .playerService,
                                          session: _session,
                                          videoTitle: _currentItem.title,
                                          settingsKey: _settingsKey,
                                          sourceQualities:
                                              decodeSourceQualities(
                                                  _baseItem.metadata[
                                                      'qualities']),
                                          sourceQualityListenable:
                                              _sourceQuality,
                                          onOpenPanel: (view, anchor) =>
                                              _openSettings(anchor,
                                                  view: view),
                                        )
                                      : PlayerControls(
                                    player:
                                        widget.dependencies.playerService,
                                    session: _session,
                                    onOpenSettings: _openSettings,
                                    videoTitle: _currentItem.title,
                                    settingsKey: _settingsKey,
                                  ),
                                ),
                              ),
                            ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// D-pad/teclado com a barra oculta (F1, Fase 4b, spec 18): setas
  /// buscam/volume e reexibem; OK (enter, numpad ou select do
  /// DPAD_CENTER) so reexibe; espaco alterna play/pause e reexibe.
  /// Handler global em vez de binding: independe de onde o foco caiu
  /// (no aparelho, os bindings nao disparavam). So age com esta rota no
  /// topo e sem painel/overlay; fora disso devolve false para
  /// traversal, botoes e dialogos resolverem. O true consome: cada
  /// tecla executa uma unica vez.
  bool _handleHiddenKeys(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (_controlsVisible || _panelOpen || _overlayUp) return false;
    final context = _screenFocus.context;
    if (context == null || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final player = widget.dependencies.playerService;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        player.seekBy(-AppConstants.seekStep);
        _poke();
        return true;
      case LogicalKeyboardKey.arrowRight:
        player.seekBy(AppConstants.seekStep);
        _poke();
        return true;
      case LogicalKeyboardKey.arrowUp:
        player.setVolume((_session.volume + 0.1).clamp(0.0, 1.0));
        _poke();
        return true;
      case LogicalKeyboardKey.arrowDown:
        player.setVolume((_session.volume - 0.1).clamp(0.0, 1.0));
        _poke();
        return true;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.select:
        _poke();
        return true;
      case LogicalKeyboardKey.space:
        _session.status == PlaybackStatus.playing
            ? player.pause()
            : player.play();
        _poke();
        return true;
      default:
        return false;
    }
  }
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final player = widget.dependencies.playerService;
    // Setas na TV (Fase 4, spec 18): com controles visiveis, as setas
    // NAVEGAM o foco (sem binding, vale o traversal direcional padrao,
    // e o slider focado responde sozinho). Com a barra oculta, tudo
    // passa pelo handler global [_handleHiddenKeys] (F1, Fase 4b): no
    // aparelho os bindings nao disparavam mesmo com o foco dentro da
    // subarvore. Com painel ou overlay modal, nada de seek/espaco: as
    // teclas pertencem ao dialogo (Enter ativa o botao focado).
    final modalUp = _panelOpen || _overlayUp;
    return {
      // Espaco visivel alterna play/pause; oculto, o handler global
      // cuida (so um dos dois existe por vez: sem disparo duplo).
      if (!modalUp && _controlsVisible)
        const SingleActivator(LogicalKeyboardKey.space): () {
          _session.status == PlaybackStatus.playing
              ? player.pause()
              : player.play();
          _poke();
        },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        player.setMuted(!_session.isMuted);
        _poke();
      },
      const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      const SingleActivator(LogicalKeyboardKey.keyI): () =>
          _openSettingsAt(PlayerPanelView.info),
      const SingleActivator(LogicalKeyboardKey.keyS): () =>
          _openSettingsAt(PlayerPanelView.subtitles),
      const SingleActivator(LogicalKeyboardKey.keyA): () =>
          _openSettingsAt(PlayerPanelView.audio),
      // C alterna o cinema: nao esta na tabela da spec 12.3, mas o modo
      // precisa de entrada por teclado quando a barra some (Esc sai).
      const SingleActivator(LogicalKeyboardKey.keyC): () {
        _toggleCinema();
        _poke();
      },
      const SingleActivator(LogicalKeyboardKey.escape): _onBack,
      const SingleActivator(LogicalKeyboardKey.keyQ): () {
        // A saida passa pelo PopScope, que salva a sessao antes de fechar.
        if (!_panelOpen) Navigator.of(context).maybePop();
      },
    };
  }

  void _poke() {
    final wasHidden = !_controlsVisible;
    setState(() => _controlsVisible = true);
    _scheduleHide();
    // Reexibir depois de oculto: o foco morreu com a barra, ancora de
    // novo num controle (sem roubar o foco de quem ja tem um valido,
    // ex. mouse sobre a barra apos Tab).
    if (wasHidden) _restoreFocusIfLost();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(AppConstants.controlsAutoHide, () {
      // No modo TV a barra persiste navegando nela (spec 12.2); fora
      // dele, esconde mesmo com foco (comportamento desktop).
      if (mounted && !_panelOpen && !_overlayUp && !(_tvMode && _controlsScope.hasFocus)) {
        setState(() => _controlsVisible = false);
        final current = FocusManager.instance.primaryFocus;
        // focusedChild e grudento (ultimo, nao atual): so guarda com o
        // foco DENTRO da barra; fora dela, null pede o proximo da ordem.
        _lastControlFocus = current != null &&
                current.ancestors.contains(_controlsScope)
            ? current
            : null;
        // Ancorar no no da tela: sem isso o foco cai no escopo da rota
        // e a primeira seta do D-pad se perde. Com overlay modal, nao
        // rouba: o autofocus do botao primario vale (F2, Fase 4b).
        if (!_overlayUp) _screenFocus.requestFocus();
      }
    });
  }

  /// Devolve o foco a um controle quando ele se perdeu (card ocultado
  /// e reexibido, overlay fechado, cantos ocultos). So age quando o
  /// foco atual e nulo, o no raiz ou sem contexto: nunca rouba um foco
  /// valido. Pos-frame porque a arvore-alvo pode estar remontando.
  void _restoreFocusIfLost() {
    final current = FocusManager.instance.primaryFocus;
    final lost = current == null ||
        current == _screenFocus ||
        current.context == null;
    if (!lost || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _lastControlFocus;
      if (target != null && target.context != null && target.canRequestFocus) {
        target.requestFocus();
      } else {
        FocusScope.of(context).nextFocus();
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    await widget.dependencies.windowService.setFullscreen(next);
    if (!mounted) return;
    setState(() {
      _fullscreen = next;
      _controlsVisible = true;
    });
    // Os cantos ocultam/exibem: o foco pode ter morrido com eles.
    // Ancorar no no raiz mataria as setas (nada fora de um retangulo
    // de tela cheia), entao restaura num controle de verdade.
    _restoreFocusIfLost();
    _scheduleHide();
  }

  Future<void> _toggleCompact() async {
    final windows = widget.dependencies.windowService;
    final next = !(await windows.isCompact);
    await windows.setCompact(next);
    if (!next) {
      // Restaura a preferencia de topo ao sair do compacto.
      await windows.setAlwaysOnTop(
          widget.dependencies.preferencesService.current.alwaysOnTop);
    }
    if (!mounted) return;
    setState(() => _compact = next);
  }

  /// Modo cinema (spec 14.2): o video ocupa o interior da janela e a
  /// barra do app some; os controles continuam flutuando sobre o video.
  /// Nao mexe na janela do sistema (isso e tela cheia). Sai com C ou Esc.
  void _toggleCinema() {
    setState(() => _cinema = !_cinema);
    _restoreFocusIfLost();
  }

  /// Hierarquia do voltar (spec 18 + cinema): menu -> tela cheia ->
  /// cinema -> salvar e sair. A saida final passa pelo PopScope, que
  /// salva antes de fechar.
  void _onBack() {
    if (_panelOpen) {
      Navigator.of(context).pop();
    } else if (_fullscreen) {
      _toggleFullscreen();
    } else if (_cinema) {
      _toggleCinema();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openSettings(
    BuildContext? anchorContext, {
    PlayerPanelView view = PlayerPanelView.main,
  }) async {
    setState(() {
      _panelOpen = true;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
    final prefs = widget.dependencies.preferencesService.current;
    final animations = prefs.animations;
    await PlayerSettingsPanel.show(
      context,
      anchorContext: anchorContext,
      player: widget.dependencies.playerService,
      session: _session,
      videoTitle: _currentItem.title,
      preferredAudio: prefs.defaultAudio,
      preferredSubtitle: prefs.defaultSubtitle,
      sourceLabel: sourceLabelFor(_currentItem),
      sourceQualities:
          decodeSourceQualities(_baseItem.metadata['qualities']),
      selectedSourceQualityId: _sourceQuality.value,
      sourceQualityListenable: _sourceQuality,
      onSelectSourceQuality: _switchSourceQuality,
      initialView: view,
      transitionDuration:
          animations ? AppConstants.shortTransition : Duration.zero,
    );
    if (mounted) {
      setState(() => _panelOpen = false);
      _scheduleHide();
    }
  }

  /// Atalhos I/S/A (spec 12.3): abrem o painel direto na subview.
  /// Agenda para o proximo frame para que a barra (e a ancora do botao
  /// de configuracoes) esteja visivel: o painel ancora no icone, nunca
  /// solto num canto (spec 3.5).
  void _openSettingsAt(PlayerPanelView view) {
    if (_panelOpen) return;
    _poke();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _panelOpen) return;
      _openSettings(_settingsKey.currentContext, view: view);
    });
  }

  /// Troca de rendicao da fonte (5C): reabre na URL da rendicao
  /// (null volta a URL padrao) preservando a posicao. O id segue o
  /// mesmo: historico e retomada nao se dividem por qualidade.
  Future<void> _switchSourceQuality(String? qualityId) async {
    final qualities =
        decodeSourceQualities(_baseItem.metadata['qualities']);
    var source = _baseItem.source;
    if (qualityId != null) {
      var found = false;
      for (final quality in qualities) {
        if (quality.id == qualityId) {
          source = quality.sourceUrl;
          found = true;
        }
      }
      if (!found) return;
    }
    final player = widget.dependencies.playerService;
    final position = player.session.position;
    final next = _baseItem.copyWith(source: source);
    await player.open(next);
    await player.seek(position);
    if (!mounted) return;
    setState(() {
      _sourceQuality.value = qualityId;
      _currentItem = next;
    });
    _poke();
  }

  /// Reve o video do inicio (acao final, spec 11).
  Future<void> _replay() async {
    final player = widget.dependencies.playerService;
    await player.seek(Duration.zero);
    await player.play();
    _poke();
  }

  /// Proximo item (spec 11): o mais recente do historico ainda nao
  /// concluido (exceto o atual); sem historico util, o seguinte na
  /// biblioteca em ordem de adicao. Null quando nao ha proximo.
  MediaItem? get _nextItem {
    final library = widget.dependencies.libraryService;
    final history = widget.dependencies.historyService;
    for (final entry in history.entries) {
      if (entry.mediaId == _currentItem.id || entry.completed) continue;
      final item = library.findById(entry.mediaId);
      if (item != null) return item;
    }
    final items = library.items;
    final index = items.indexWhere((item) => item.id == _currentItem.id);
    for (var i = index + 1; i < items.length; i++) {
      final candidate = items[i];
      final entry = history.latestFor(candidate.id);
      if (entry == null || !entry.completed) return candidate;
    }
    return null;
  }

  /// Avanca sozinho ao fim do video quando a preferencia manda (spec 11).
  /// Com repeticao ligada o proprio player faz o loop; com o painel
  /// aberto, espera o usuario (o botao Proximo continua la).
  Future<void> _maybeAutoAdvance() async {
    if (_panelOpen) return;
    if (_session.repeatMode != PlaybackRepeatMode.off) return;
    if (!widget.dependencies.preferencesService.current.autoplayNext) {
      return;
    }
    final next = _nextItem;
    if (next == null) return;
    await _playNext(next);
  }

  /// Salva a sessao concluida e troca o item sem empilhar rotas.
  /// Leva a posicao salva do proximo junto, como as telas de inicio
  /// e historico fazem ao mandar reproduzir.
  Future<void> _playNext(MediaItem next) async {
    await _saveSession();
    if (!mounted) return;
    final entry =
        widget.dependencies.historyService.latestFor(next.id);
    final target = entry == null
        ? next
        : next.copyWith(lastPosition: () => entry.position);
    Navigator.of(context)
        .pushReplacementNamed(AppRoutes.player, arguments: target);
  }

  /// Favorito atual lido da biblioteca (o item da rota e uma copia e
  /// ficaria obsoleto apos alternar).
  bool get _isFavorite =>
      widget.dependencies.libraryService
          .findById(_currentItem.id)
          ?.isFavorite ??
      _currentItem.isFavorite;

  Future<void> _toggleFavorite() async {
    await widget.dependencies.libraryService
        .toggleFavorite(_currentItem.id);
    if (mounted) setState(() {});
  }

  /// Casa o idioma preferido com as faixas (spec 16): igualdade com o
  Future<void> _applyPreferredAudio(PlaybackSession session) async {
    final player = widget.dependencies.playerService;
    final id = findTrackForLanguage(session.audioTracks,
        widget.dependencies.preferencesService.current.defaultAudio);
    if (id != null) await player.selectAudio(id);
  }

  Future<void> _applyPreferredSubtitles(PlaybackSession session) async {
    final player = widget.dependencies.playerService;
    final prefs = widget.dependencies.preferencesService.current;
    final id =
        findTrackForLanguage(session.subtitleTracks, prefs.defaultSubtitle);
    if (id != null) {
      await player.selectSubtitle(id);
    } else if (!prefs.subtitlesByDefault) {
      await player.selectSubtitle(null);
    }
  }

  /// Localiza o arquivo novamente (spec 17.5): procura outro caminho,
  /// atualiza o MESMO item (titulo e fonte zeram; posicao idem) e tenta
  /// de novo sem sair da tela. Nada e copiado nem apagado.
  Future<void> _relocate() async {
    final files = await FilePicker.pickFiles(
      type: FileType.video,
      dialogTitle: 'Localizar arquivo',
    );
    final path = files.singleOrNull?.path;
    if (path == null || path.isEmpty) return;
    final updated = await widget.dependencies.libraryService.upsert(
      _currentItem.copyWith(
        title: titleFromSource(path),
        source: path,
        duration: () => null,
        lastPosition: () => null,
      ),
    );
    if (!mounted) return;
    setState(() {
      // Novo arquivo = nova base: rendicao anterior nao vale mais.
      _currentItem = updated;
      _baseItem = updated;
      _sourceQuality.value = null;
    });
    await _open();
  }

  /// Remove o item da biblioteca e do historico e sai (spec 17.5). O
  /// arquivo original nunca e tocado. Sai sem salvar a sessao.
  Future<void> _removeFromLibrary() async {
    // F3 (Fase 4b): remocao pede confirmacao (Cancelar focado, §26.6).
    final confirmed = await confirmDestructiveAction(
      context,
      title: "Remover da biblioteca?",
      message: "'${_currentItem.title}' sai da biblioteca e do histórico. O arquivo original não é apagado.",
    );
    if (!confirmed) return;
    await widget.dependencies.libraryService.remove(_currentItem.id);
    await widget.dependencies.historyService.remove(_currentItem.id);
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  /// Editar link (spec 17.2): abre a tela de link com o endereco atual
  /// preenchido, trocando a rota (sem salvar a sessao com erro).
  void _editLink() {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.openMedia,
      arguments: OpenMediaArgs(
        tab: OpenMediaTab.link,
        initialValue: _currentItem.source,
      ),
    );
  }

  /// Salva a posicao e pausa (spec 11, 19). Chamado pelo PopScope antes
  /// de fechar; nao navega sozinho. Com "Lembrar posicao" desligado,
  /// apenas pausa: nada e registrado. Sem informacao nova (posicao zero,
  /// sem duracao) sobre uma retomada anterior, tambem nao registra:
  /// preserva o ponto salvo (abertura falhada na TV). Estreia sem
  /// progresso registra normal (visita aparece no historico).
  Future<void> _saveSession() async {
    // Le o motor (fresco), nao o espelho: no BACK o evento de erro pode
    // ainda nao ter chegado ao listener do widget.
    final live = widget.dependencies.playerService.session;
    final position = live.position;
    final duration = live.duration;
    // Sem informacao nova nao sobrescreve retomada anterior: sair com
    // erro ou antes do primeiro frame apagaria o ponto salvo (TV).
    final prior = _currentItem.lastPosition;
    final hadResume = prior != null && prior > Duration.zero;
    final hasProgress = position > Duration.zero || duration != null;
    if (widget.dependencies.preferencesService.current.rememberPosition &&
        (hasProgress || !hadResume)) {
      final history = widget.dependencies.historyService;
      final library = widget.dependencies.libraryService;
      final completed = duration != null &&
          duration > Duration.zero &&
          position >= duration - const Duration(seconds: 5);
      await history.record(HistoryEntry(
        mediaId: _currentItem.id,
        accessedAt: DateTime.now(),
        position: position,
        percentWatched: duration == null || duration.inMilliseconds == 0
            ? null
            : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0),
        completed: completed,
      ));
      final stored = library.findById(_currentItem.id);
      if (stored != null) {
        await library.upsert(stored.copyWith(
          duration: () => duration,
          lastPosition: () => position,
          lastPlayedAt: () => DateTime.now(),
        ));
      }
    }
    await widget.dependencies.playerService.pause();
  }
}

/// Area do video: superficie da implementacao com estados sobrepostos
/// (carregando, erro, fim). A tela nao conhece a biblioteca de video.
class _VideoArea extends StatelessWidget {
  const _VideoArea({
    required this.player,
    required this.session,
    required this.isLocal,
    required this.onRetry,
    required this.onCancel,
    required this.onRelocate,
    required this.onRemoveFromLibrary,
    required this.onEditLink,
    required this.onReplay,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.nextTitle,
    required this.onPlayNext,
    required this.onClose,
    required this.primaryFocus,
  });

  final MediaPlayerService player;
  final PlaybackSession session;

  /// Erro de arquivo local (spec 17.1, 17.5) ou de link (spec 17.2):
  /// cada tipo tem suas acoes.
  final bool isLocal;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onRelocate;
  final VoidCallback onRemoveFromLibrary;
  final VoidCallback onEditLink;

  /// Acoes finais (spec 11): rever, favoritar, proximo e fechar.
  final VoidCallback onReplay;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final String? nextTitle;
  final VoidCallback? onPlayNext;
  final VoidCallback onClose;
  final FocusNode primaryFocus;

  /// Mensagem pelo TIPO do erro, nunca a string nativa (pode conter
  /// caminhos e URLs). Cada tipo diz de quem e a culpa: rede, fonte,
  /// decodificador ou tempo esgotado — nunca o player por um erro da
  /// fonte (spec 26).
  String _messageFor(PlaybackSession session) {
    return switch (session.errorKind) {
      // Fonte local nunca e problema de rede (F9, Fase 4b): o mpv
      // relata "Failed to open ... Permission denied" e o
      // classificador ja mapeia permissao para fonte; este guarda
      // cobre qualquer outro texto classificado como rede.
      PlaybackErrorKind.network => isLocal
          ? const MediaError.missingFile().message
          : const NetworkError.offline().message,
      PlaybackErrorKind.source => isLocal
          ? const MediaError.missingFile().message
          : const NetworkError.unavailableLink().message,
      PlaybackErrorKind.decoder =>
        const MediaError.incompatible().message,
      PlaybackErrorKind.timeout =>
        'A fonte demorou demais a responder. Tente de novo ou volte.',
      PlaybackErrorKind.unknown || null => isLocal
          ? 'Não foi possível reproduzir este arquivo neste dispositivo.'
          : 'Não foi possível carregar este link. Verifique a conexão ou confirme se o endereço ainda está disponível.',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (session.status == PlaybackStatus.error) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Não foi possível reproduzir',
        message: _messageFor(session),
        actions: [
          FocusableButton(
            label: 'Tentar novamente',
            focusNode: primaryFocus,
            icon: Icons.refresh,
            primary: true,
            autofocus: true,
            onPressed: onRetry,
          ),
          if (isLocal)
            FocusableButton(
              label: 'Localizar arquivo…',
              icon: Icons.folder_open,
              onPressed: onRelocate,
            )
          else
            FocusableButton(
              label: 'Editar link',
              icon: Icons.edit,
              onPressed: onEditLink,
            ),
          if (isLocal)
            FocusableButton(
              label: 'Remover da biblioteca',
              icon: Icons.delete_outline,
              onPressed: onRemoveFromLibrary,
            ),
          FocusableButton(
            label: 'Fechar',
            icon: Icons.close,
            onPressed: onClose,
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RotatedBox(
          quarterTurns: session.rotation,
          child: player.buildVideoView(),
        ),
        if (session.status == PlaybackStatus.loading ||
            session.status == PlaybackStatus.buffering)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                FocusableButton(
                  label: 'Cancelar',
                  icon: Icons.close,
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        if (session.status == PlaybackStatus.completed)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Reprodução concluída',
                      style:
                          TextStyle(color: PlayerTheme.primaryText)),
                  if (nextTitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'A seguir: $nextTitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: PlayerTheme.secondaryText),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FocusableButton(
                        label: 'Reproduzir novamente',
                        focusNode: primaryFocus,
                        icon: Icons.replay,
                        primary: true,
                        autofocus: true,
                        onPressed: onReplay,
                      ),
                      FocusableButton(
                        label: isFavorite
                            ? 'Remover dos favoritos'
                            : 'Adicionar aos favoritos',
                        icon: isFavorite
                            ? Icons.favorite
                            : Icons.favorite_outline,
                        onPressed: onToggleFavorite,
                      ),
                      if (nextTitle != null && onPlayNext != null)
                        FocusableButton(
                          label: 'Próximo',
                          icon: Icons.skip_next,
                          onPressed: onPlayNext,
                        ),
                      FocusableButton(
                        label: 'Fechar',
                        icon: Icons.close,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Politica direcional do player (Fase 4): subir do card de controles
/// ancora no botao dos cantos mais proximo, em vez de cair no slider
/// de progresso (faixa de largura total que capturaria todo raio
/// para cima e bipartiria a tela). Sem cantos (cinema) ou fora das
/// setas para cima, vale o padrao. Tab segue a ordem de leitura.
class _PlayerTraversalPolicy extends ReadingOrderTraversalPolicy {
  _PlayerTraversalPolicy({
    required this.controlsScope,
    required this.cornerScope,
  });

  final FocusScopeNode controlsScope;
  final FocusScopeNode cornerScope;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final upFromControls = direction == TraversalDirection.up &&
        currentNode.ancestors.contains(controlsScope);
    final downFromCorners = direction == TraversalDirection.down &&
        currentNode.ancestors.contains(cornerScope);
    if (upFromControls || downFromCorners) {
      final target = upFromControls
          ? _nearestAbove(currentNode)
          : _nearestBelow(currentNode);
      if (target != null) {
        // Nao chama o super aqui de proposito: o padrao agenda um
        // foco adiado na borda do escopo que puxaria o foco de volta
        // depois deste salto (coberto pelo teste do loop cantos <->
        // slider). Nos demais casos, o super resolve abaixo.
        target.requestFocus();
        return true;
      }
    }
    return super.inDirection(currentNode, direction);
  }

  /// Focavel dos cantos mais proximo acima de [current], ou null sem
  /// cantos montados (cinema) ou sem candidato.
  FocusNode? _nearestAbove(FocusNode current) {
    if (cornerScope.children.isEmpty) return null;
    return _nearestIn(cornerScope, current, above: true);
  }

  /// Focavel do card mais proximo abaixo de [current] (na pratica,
  /// o slider de progresso).
  FocusNode? _nearestBelow(FocusNode current) {
    if (controlsScope.children.isEmpty) return null;
    return _nearestIn(controlsScope, current, above: false);
  }

  /// Vizinho focavel mais proximo de [current] dentro de [scope],
  /// acima ou abaixo dele. Escopos nunca sao alvo.
  FocusNode? _nearestIn(FocusScopeNode scope, FocusNode current, {required bool above}) {
    final origin = current.rect.center;
    FocusNode? best;
    var bestDistance = double.infinity;
    void visit(FocusNode node) {
      for (final child in node.children) {
        final inBand = above
            ? child.rect.center.dy < origin.dy
            : child.rect.center.dy > origin.dy;
        if (child is! FocusScopeNode &&
            child.canRequestFocus &&
            !child.skipTraversal &&
            child.context != null &&
            inBand) {
          // Eixo vertical domina, horizontal desempatia: a faixa do
          // slider (largura total) venceria pelo centro em distancia
          // euclidiana pura.
          final delta = child.rect.center - origin;
          final distance = delta.dy.abs() * 4096 + delta.dx.abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            best = child;
          }
        }
        visit(child);
      }
    }

    visit(scope);
    return best;
  }
}
