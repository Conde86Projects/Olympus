import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player/app/app.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/hls_cold_probe.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/history_entry.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_permission_service.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/services/mobile_chrome_service.dart';
import 'package:player/services/supervised_player_service.dart';
import 'package:player/services/system_volume_service.dart';
import 'package:player/services/thumbnail_service.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/core/utils/volume_step.dart';
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

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  StreamSubscription<PlaybackSession>? _subscription;
  StreamSubscription<void>? _minimizedSub;

  /// Sistema zerado/mudo (Android): o ícone de mudo reflete também o
  /// aparelho, não só o estado interno. Desktop ignora (sem canal).
  bool _systemSilent = false;
  StreamSubscription<SystemVolumeState>? _systemVolumeSub;

  /// Gravacao no X do sistema (Windows). Referencia estavel para
  /// remover so a deste player no dispose.
  late final Future<void> Function() _saveOnWindowClose = _saveSession;
  PlaybackSession _session = const PlaybackSession();
  Timer? _resumeTimer;

  /// Visibilidade dos controles (dona: MobileChrome, F2/#7): a tela lê
  /// e reage via `ListenableBuilder`, sem copiar estado nem gerir timer.
  bool get _controlsVisible => _chrome.controlsVisible;

  /// Chrome mobile (dono do estado de tela cheia NO CELULAR, F1/#6):
  /// a tela lê [_fullscreen] e assina mudanças; nunca mantém cópia local.
  /// Desktop/TV seguem no espelho local abaixo (dono futuro, fora da F1).
  late final MobileChromeService _chrome;
  bool _windowFullscreen = false;
  bool get _fullscreen => _mobile ? _chrome.isFullscreen : _windowFullscreen;
  bool _compact = false;
  bool _cinema = false;
  bool _panelOpen = false;
  bool _allowPop = false;

  /// Saida intencional em curso (ver [_exitPlayer]).
  bool _exitRequested = false;

  /// Oferta "Ver de novo" (spec 11, Fase 0.2.0): reabertura de item
  /// concluido comeca do inicio e mostra a acao; some ao usar,
  /// fechar, errar ou concluir de novo.
  bool _replayOffer = false;

  /// Abertura atual veio de item concluido: o progresso se mede do
  /// zero (replay), nao da posicao final salva; sair sem assistir
  /// preserva o historico concluido.
  bool _openedCompleted = false;

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

  /// Selecao HLS manual (id da opcao; Automática e o padrao) e as
  /// variantes reais do master ja buscadas. Reabrir na variante
  /// preserva item/historico: o id segue o do master.
  late final ValueNotifier<String> _hlsQuality;
  List<HlsVariant> _hlsVariants = const [];

  /// Qualidade efetivamente aberta (rotulo da variante; null =
  /// master/Original). Visivel na linha Qualidade do painel.
  late final ValueNotifier<String?> _hlsEffective;

  /// Observador de capacidade (TV, Automatica): amostra
  /// posicao/relogio nos primeiros segundos e desce um degrau
  /// uma unica vez por abertura se ficar abaixo do limiar.
  Timer? _hlsObserveTimer;

  /// Redetecção fria (uma única tentativa posterior, limitada): só
  /// aquece [_hlsVariants] para o seletor; nunca reabre nem troca.
  Timer? _hlsColdTimer;
  bool _hlsAutoDowngraded = false;
  DateTime? _obsAt;
  Duration? _obsPos;

  /// Posição HLS não verificada (retomada ou troca de qualidade
  /// com pouso fora da tolerância): pausa de segurança e preserva
  /// o histórico do ponto errado. Vale até nova abertura ou nova
  /// localização de arquivo.
  bool _hlsPositionProtect = false;

  /// Leituras da sonda de retomada HLS (só leitura, sem seeks).
  Timer? _resumeProbeTimer;

  /// Cobertura do vídeo enquanto a retomada/troca de qualidade HLS
  /// leva a imagem ao ponto salvo. O gate de prontidão (validado na
  /// TCL) exige o primeiro avanço real antes do seek, então o início
  /// do vídeo chegava a aparecer (título) antes de pular. Só visual:
  /// nada aqui chama o player, a lógica de posição não muda.
  bool _repositioning = false;
  Timer? _repositionTimer;

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
  late final _PlayerTraversalPolicy _traversalPolicy = _PlayerTraversalPolicy(
    controlsScope: _controlsScope,
    cornerScope: _cornerScope,
  );

  bool get _tvMode => widget.dependencies.preferencesService.current.tvMode;

  /// Android/iOS (celular e TV física): o volume é do sistema/aparelho.
  /// Nomes espelham [PlayerApp.mobilePlatform] (produção), mas aqui a
  /// abertura roda no initState, sem inherited widget: vale a
  /// plataforma-alvo direta.
  bool get _isMobileOs =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Janela baixa no desktop (compacto 480x270, janela pequena): card
  /// de uma fileira e cantos de 36. Recalculado a cada build; acima do
  /// limite o desenho do desktop segue pixel a pixel.
  bool _dense = false;

  /// Celular ([MobileMode]): toque, sem hover nem D-pad. Recalculado a
  /// cada build. Cantos de 48, toque alterna os controles, toque duplo
  /// nas laterais busca 10 s, tela cheia imersiva em paisagem.
  bool _mobile = false;

  /// Rotulo rapido do toque duplo ("-10 s"/"+10 s") e o lado dele.
  String? _seekFlash;
  bool _seekFlashLeft = false;
  Timer? _seekFlashTimer;

  /// Ponto do ultimo toque duplo (decide o lado da busca).
  Offset? _doubleTapAt;

  /// Cantos na TV e na janela baixa: botoes de 36 como a barra (spec
  /// 27.6); 48 no celular. Null no desktop: o desenho atual segue
  /// pixel a pixel.
  double? get _cornerSize {
    if (_tvMode) return 36.0;
    if (_mobile) return MobileMode.minTouchTarget;
    return _dense ? 36.0 : null;
  }

  /// Respiro dos cantos na TV e na janela baixa (glifo de 20 em botao
  /// de 36); 12 no celular (glifo de 24 em 48). Null no desktop: vale
  /// o padrao do botao.
  EdgeInsetsGeometry? get _cornerPadding {
    if (_tvMode) return const EdgeInsets.all(8);
    if (_mobile) return const EdgeInsets.all(12);
    return _dense ? const EdgeInsets.all(8) : null;
  }

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _baseItem = widget.item;
    _chrome = widget.dependencies.mobileChromeService;
    // Nova sessão sempre abre visível (era o inicializador do campo).
    _chrome.showControls();
    // Guarda do auto-hide avaliada no disparo (painel/overlay seguram);
    // gancho de foco após ocultar no disparo.
    _chrome.autoHideGuard = () => mounted && !_panelOpen && !_overlayUp;
    _chrome.onControlsAutoHidden = _anchorFocusOnHide;
    _sourceQuality = ValueNotifier<String?>(null);
    _hlsQuality = ValueNotifier<String>(HlsVariants.autoQualityId);
    _hlsEffective = ValueNotifier<String?>(null);
    // Ao sair da barra no modo TV, rearma o auto-hide (e so).
    _controlsScope.addListener(() {
      if (mounted &&
          _controlsVisible &&
          _tvMode &&
          !_panelOpen &&
          !_controlsScope.hasFocus) {
        _chrome.pokeControls();
      }
    });
    final player = widget.dependencies.playerService;
    _subscription = player.sessionStream.listen((session) {
      if (!mounted) return;
      final was = _session.status;
      setState(() {
        _session = session;
        if (session.status == PlaybackStatus.error ||
            session.status == PlaybackStatus.completed) {
          _replayOffer = false;
        }
      });
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
      if (session.status == PlaybackStatus.error &&
          was != PlaybackStatus.error &&
          _panelOpen &&
          _hlsVariants.isNotEmpty &&
          _hlsQuality.value != HlsVariants.autoQualityId) {
        // Falha da variante com o painel aberto: fecha o painel
        // para o erro controlado (overlay) aparecer com a volta
        // para Automatica alcancavel.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _panelOpen) Navigator.of(context).pop();
        });
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
    WidgetsBinding.instance.addObserver(this);
    _minimizedSub = widget.dependencies.windowService.minimized
        .listen((_) => unawaited(_saveSession(pause: false)));
    widget.dependencies.windowService.addBeforeClose(_saveOnWindowClose);
    // Volume do sistema (Android): zerou no aparelho → mostra mudo;
    // aumentou → despluga o mudo do app (a tecla física também faz
    // isso em [_handleHiddenKeys]; aqui cobre ajuste pelo painel e
    // garante o ícone certo).
    if (_isMobileOs) {
      final volumes = widget.dependencies.systemVolumeService;
      unawaited(volumes.current().then((state) {
        if (!mounted) return;
        setState(() => _systemSilent = state.isSilent);
      }));
      _systemVolumeSub = volumes.watch().listen((state) {
        if (!mounted) return;
        setState(() => _systemSilent = state.isSilent);
        if (!state.isSilent && _session.isMuted) {
          unawaited(
              widget.dependencies.playerService.setMuted(false));
        }
      });
    }
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
    _hlsAutoDowngraded = false;
    _hlsObserveTimer?.cancel();
    _hlsColdTimer?.cancel();
    _hlsColdTimer = null;
    _hlsPositionProtect = false;
    _replayOffer = false;
    _replayOffer = false;
    _openedCompleted = false;
    var openItem = _currentItem;
    // Teto HLS por classe (SoC fraco): compacto/normal abrem a
    // variante <=720p; grande (4K) segue no master. Falha, timeout
    // ou playlist simples: abre a URL original. O item salvo segue
    // o master (variante expira; resolve de novo a cada abertura).
    // Sem inherited widget (roda no initState): tvMode vem da pref
    // e a largura direto da view; 1280 e o piso da classe grande
    // (spec 27.4).
    if (openItem.sourceType == MediaSourceType.url &&
        _isCappedClass &&
        _isM3u8Url(_baseItem.source)) {
      // Classe com teto: busca as variantes reais uma vez e abre
      // pela selecao (Automatica = teto atual, sem mudanca).
      final variants = await HlsVariants.fetchVariants(_baseItem.source);
      _hlsVariants = variants;
      if (_hlsVariants.isEmpty) {
        // Rede fria: abre o master agora (fallback abaixo) e agenda
        // no máximo UMA redetecção limitada posterior, só para
        // aquecer a lista do seletor — sem trocar qualidade, sem
        // reabrir, sem buscar posição e sem tocar histórico/ID.
        _scheduleHlsColdWarm();
      }
      final target = _hlsTarget(
        _hlsQuality.value,
        _baseItem.source,
        variants,
      );
      openItem = _baseItem.copyWith(source: target);
      _currentItem = openItem;
    } else if (openItem.sourceType == MediaSourceType.url &&
        _hlsQuality.value != HlsVariants.autoQualityId &&
        _hlsVariants.isNotEmpty) {
      // Retry apos troca manual: respeita a selecao vigente.
      final target = _hlsTarget(
        _hlsQuality.value,
        _baseItem.source,
        _hlsVariants,
      );
      openItem = _baseItem.copyWith(source: target);
      _currentItem = openItem;
    }
    final coverResume =
        widget.dependencies.preferencesService.current.resumeAutomatically &&
            _isM3u8Url(_baseItem.source) &&
            (_currentItem.lastPosition ?? Duration.zero) > Duration.zero;
    if (coverResume) _beginReposition(player);
    await player.open(openItem);
    // Aplica preferencias de reproducao apos abrir (spec 16).
    final prefs = widget.dependencies.preferencesService.current;
    await player.setSpeed(prefs.defaultSpeed);
    // Volume interno (initialVolume) só no desktop/Windows. No celular
    // vale o volume do sistema e na TV o da TV (VOL+/VOL− do controle
    // remoto, fora do app): nessas plataformas o Olympus oferece só o
    // mudo e nunca impõe nem salva volume interno.
    if (!_tvMode && !_isMobileOs) {
      await player.setVolume(prefs.initialVolume);
    }
    // As faixas costumam chegar depois: vale o que existir agora e o
    // restante e aplicado pelo listener quando chegar.
    await _applyPreferredAudio(player.session);
    await _applyPreferredSubtitles(player.session);
    // Item concluido (spec 11, Fase 0.2.0): reabre do inicio, sem
    // buscar a posicao final; a oferta "Ver de novo" aparece no overlay.
    final wasCompleted = widget.dependencies.historyService
            .latestFor(_currentItem.id)
            ?.completed ??
        false;
    if (wasCompleted && mounted) {
      setState(() {
        _replayOffer = true;
        _openedCompleted = true;
      });
    }
    final resume = wasCompleted ? null : _currentItem.lastPosition;
    if (prefs.resumeAutomatically && resume != null && resume > Duration.zero) {
      // TV-RESUME (TV fisica, mpv frio): seek disparado antes de o mpv
      // conhecer o arquivo e descartado em silencio -- a retomada so
      // vale depois da duracao chegar (com timeout para nao travar
      // arquivo quebrado: o erro segue o fluxo normal).
      await _waitForDuration(player, const Duration(seconds: 5));
      if (!mounted) return;
      if (await _isHlsMaster()) {
        // Master HLS: seek com verificacao da posicao real e no
        // maximo UMA correcao (resume HLS). Os demais fluxos
        // seguem exatamente como estavam.
        await _resumeHlsMaster(player, resume);
      } else {
        await player.seek(resume);
        _verifyResume(player, resume);
      }
    }
    if (prefs.autoplay) {
      await player.play();
    }
    if (mounted) {
      setState(() => _session = player.session);
      if (_isM3u8Url(_baseItem.source)) {
        _hlsEffective.value = _effectiveLabelFor(openItem.source);
      } else {
        _hlsEffective.value = null;
      }
      _startHlsObserver();
      // Reexibe (retry apos erro) e rearma; sem isso o retry voltava
      // tocando com a barra oculta e o foco orfao (F2, Fase 4b).
      _poke();
      // Tentar de novo fecha o overlay modal: o foco morreu com ele.
      _restoreFocusIfLost();
    }
  }

  /// Largura logica da view principal (null sem view).
  double? get _logicalWidth {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    return views.first.physicalSize.width / views.first.devicePixelRatio;
  }

  /// Perfil automatico: plataforma + Leanback (dobrado em tvMode
  /// na abertura/manual) + viewport. Teto estatico inalterado.
  HlsAutoDecision get _autoDecision => HlsVariants.autoDecision(
        isTv: _tvMode,
        logicalWidth: _logicalWidth,
        platform: defaultTargetPlatform.name,
      );

  bool get _isCappedClass => _autoDecision.capped;

  DateTime _now() => HlsVariants.debugNowOverride?.call() ?? DateTime.now();

  /// Rotulo da variante efetivamente aberta (null = master).
  String? _effectiveLabelFor(String target) {
    if (target == _baseItem.source) return null;
    for (final variant in _hlsVariants) {
      if (variant.uri.toString() == target) {
        return HlsVariants.variantLabel(variant);
      }
    }
    return null;
  }

  static bool _isM3u8Url(String source) {
    final uri = Uri.tryParse(source);
    return uri != null && uri.path.toLowerCase().endsWith('.m3u8');
  }

  /// URL concreta de uma selecao HLS: Automatica (teto/master),
  /// Original (master) ou a variante, validada contra as reais.
  String _hlsTarget(
    String qualityId,
    String master,
    List<HlsVariant> variants,
  ) {
    if (qualityId == HlsVariants.originalQualityId) return master;
    if (qualityId != HlsVariants.autoQualityId) {
      for (final variant in variants) {
        if (variant.uri.toString() == qualityId) return qualityId;
      }
      // Variante que sumiu do master: cai na Automatica.
    }
    final decision = _autoDecision;
    return HlsVariants.automaticUrl(
      master,
      variants,
      capped: decision.capped,
      maxHeight: decision.maxHeight,
      maxBandwidth: decision.maxBandwidth,
    );
  }

  /// Opcoes HLS para o painel: Original so quando difere da
  /// Automatica tetada.
  List<HlsQualityOption> get _hlsOptions {
    if (_hlsVariants.isEmpty) return const [];
    final decision = _autoDecision;
    final auto = HlsVariants.automaticUrl(
      _baseItem.source,
      _hlsVariants,
      capped: decision.capped,
      maxHeight: decision.maxHeight,
      maxBandwidth: decision.maxBandwidth,
    );
    return HlsVariants.qualityOptions(
      _hlsVariants,
      includeOriginal: decision.capped && auto != _baseItem.source,
    );
  }

  /// Troca de qualidade HLS: reabre na URL alvo preservando item
  /// (mesmo id), historico e posicao aproximada. Falha da variante
  /// segue pelo erro controlado da sessao (overlay), de onde o
  /// usuario volta para Automatica.
  Future<void> _switchHlsQuality(String qualityId) async {
    if (qualityId != HlsVariants.autoQualityId &&
        qualityId != HlsVariants.originalQualityId &&
        !_hlsVariants.any((v) => v.uri.toString() == qualityId)) {
      return;
    }
    // Nova decisao do usuario: o observador ganha um ciclo novo
    // apenas se a escolha for a Automatica.
    _hlsAutoDowngraded = false;
    final target = _hlsTarget(qualityId, _baseItem.source, _hlsVariants);
    await _reopenHlsTarget(target, qualityId);
    if (!mounted) return;
    if (qualityId == HlsVariants.autoQualityId) {
      _startHlsObserver();
    } else {
      _hlsObserveTimer?.cancel();
    }
  }

  /// Reabre numa URL HLS concreta preservando item (mesmo id),
  /// historico e posicao aproximada, e registra a efetiva. A
  /// posição é restaurada pelo gate de prontidão (primeiro avanço
  /// real, fora de buffering) com no máximo uma correção validada;
  /// se o pouso continuar incorreto, retorna de forma controlada
  /// à qualidade anterior sem salvar o ponto errado.
  Future<void> _reopenHlsTarget(String target, String selectionId) async {
    final player = widget.dependencies.playerService;
    final position = player.session.position;
    final wasPlaying = player.session.status == PlaybackStatus.playing ||
        player.session.status == PlaybackStatus.buffering;
    final prevItem = _currentItem;
    final prevSelection = _hlsQuality.value;
    // A troca invalida qualquer verificação de retomada pendente:
    // ela miraria o alvo antigo na variante nova.
    _resumeTimer?.cancel();
    _resumeTimer = null;
    final probe = selectionId == HlsVariants.autoQualityId &&
            prevSelection == HlsVariants.autoQualityId
        ? 'downgrade'
        : 'switch';
    final next = _baseItem.copyWith(source: target);
    if (position > Duration.zero) _beginReposition(player);
    try {
      await _reopenHlsTargetCovered(player, next, prevItem, prevSelection,
          selectionId, position, wasPlaying, probe);
    } finally {
      // Mesma regra da retomada: só descobre depois de o vídeo andar a
      // partir do ponto salvo (a TV mostra o quadro antigo por um
      // instante). Sem posição a restaurar, descobre já.
      if (position > Duration.zero) {
        unawaited(_endRepositionWhenLanded(player, position));
      } else {
        _endReposition(player);
      }
    }
  }

  Future<void> _reopenHlsTargetCovered(
    MediaPlayerService player,
    MediaItem next,
    MediaItem prevItem,
    String prevSelection,
    String selectionId,
    Duration position,
    bool wasPlaying,
    String probe,
  ) async {
    final target = next.source;
    try {
      await player.open(next);
    } catch (_) {
      // Motor direto pode lancar; o supervisor converte em sessao
      // de erro. A selecao vale mesmo assim: o overlay oferece a
      // volta para Automatica.
    }
    if (!mounted) return;
    setState(() {
      _hlsQuality.value = selectionId;
      _currentItem = next;
      _hlsEffective.value = _effectiveLabelFor(target);
    });
    _poke();
    final restored = await _seekHlsPosition(
      player,
      position,
      probe: probe,
      allowCorrection: true,
    );
    if (!mounted) return;
    if (wasPlaying) {
      try {
        await player.play();
      } catch (_) {
        // Play best-effort: a posição restaurada vale de todo jeito.
      }
    }
    if (restored) return;
    // Retorno controlado à qualidade anterior: reabre e restaura
    // o ponto sem correção (uma tentativa); se também falhar,
    // pausa e protege o histórico.
    _probeHlsResume(player, '$probe-rollback', 'to=$prevSelection');
    try {
      await player.open(prevItem);
    } catch (_) {
      // Mesma tolerância da abertura direta acima.
    }
    if (!mounted) return;
    setState(() {
      _hlsQuality.value = prevSelection;
      _currentItem = prevItem;
      _hlsEffective.value = _effectiveLabelFor(prevItem.source);
    });
    _poke();
    final back = await _seekHlsPosition(
      player,
      position,
      probe: '$probe-rollback',
      allowCorrection: false,
    );
    if (!mounted) return;
    if (wasPlaying) {
      try {
        await player.play();
      } catch (_) {
        // Play best-effort, como acima.
      }
    }
    if (back) return;
    try {
      await player.pause();
    } catch (_) {
      // Pausa best-effort: a proteção abaixo vale de todo jeito.
    }
    if (!mounted) return;
    _hlsPositionProtect = true;
    _probeHlsResume(
        player,
        '$probe-fallback',
        'reason=rollback-unverified '
            'targetMs=${position.inMilliseconds} '
            'prev=$prevSelection');
  }

  /// Restaura [position] pelo gate de prontidão: aguarda o primeiro
  /// avanço real fora de buffering, executa o seek, valida o pouso
  /// após estabilização e, quando [allowCorrection] vale e o desvio
  /// excede a tolerância, tenta no máximo uma correção validada.
  /// Retorna verdadeiro só com o pouso dentro da tolerância.
  Future<bool> _seekHlsPosition(
    MediaPlayerService player,
    Duration position, {
    required String probe,
    required bool allowCorrection,
  }) async {
    if (position <= Duration.zero) {
      _probeHlsResume(player, '$probe-position', 'skipped=zero');
      return true;
    }
    final ready = await _waitForHlsReady(player);
    if (!mounted) return false;
    final atReady = player.session;
    _probeHlsResume(
        player,
        '$probe-readiness',
        'ready=$ready status=${atReady.status.name} '
            'posMs=${atReady.position.inMilliseconds} '
            'loading=${_isLoadingStatus(atReady.status)}');
    final beforeMs = atReady.position.inMilliseconds;
    final seekAt = DateTime.now();
    try {
      await player.seek(position);
    } catch (_) {
      // Seek best-effort: a validação abaixo decide.
    }
    if (!mounted) return false;
    final afterSeek = player.session;
    _probeHlsResume(
        player,
        '$probe-seek',
        'at=${seekAt.toIso8601String()} beforeMs=$beforeMs '
            'posAfterMs=${afterSeek.position.inMilliseconds} '
            'status=${afterSeek.status.name} '
            'loading=${_isLoadingStatus(afterSeek.status)}');
    await Future.delayed(HlsVariants.hlsVerifyDelay);
    if (!mounted) return false;
    final actual = player.session;
    _probeHlsResume(
        player,
        '$probe-verify',
        'posMs=${actual.position.inMilliseconds} '
            'status=${actual.status.name} '
            'loading=${_isLoadingStatus(actual.status)}');
    if (actual.status == PlaybackStatus.error ||
        actual.status == PlaybackStatus.completed) {
      _probeHlsResume(player, '$probe-correction', 'skipped=status');
      return false;
    }
    if (!HlsVariants.resumeNeedsCorrection(actual.position, position)) {
      return true;
    }
    if (!allowCorrection) {
      _probeHlsResume(player, '$probe-correction', 'skipped=rollback');
      return false;
    }
    try {
      await player.seek(position);
    } catch (_) {
      // Correção best-effort: a validação abaixo decide.
    }
    if (!mounted) return false;
    final corrected = player.session;
    _probeHlsResume(
        player,
        '$probe-correction',
        'posMs=${corrected.position.inMilliseconds} '
            'status=${corrected.status.name}');
    await Future.delayed(HlsVariants.hlsCorrectionSettle);
    if (!mounted) return false;
    final landed = player.session;
    final within =
        !HlsVariants.resumeNeedsCorrection(landed.position, position);
    _probeHlsResume(player, '$probe-settle',
        'posMs=${landed.position.inMilliseconds} within=$within');
    return within;
  }

  /// Redetecção fria: UMA tentativa posterior, limitada por
  /// timeout, em segundo plano. Só aquece [_hlsVariants] (o seletor
  /// passa a oferecer qualidade); nunca chama open/seek, nunca muda
  /// [_currentItem]/[_baseItem] e nunca escreve no histórico.
  void _scheduleHlsColdWarm() {
    _hlsColdTimer?.cancel();
    if (!_isCappedClass) return;
    if (_currentItem.sourceType != MediaSourceType.url) return;
    if (!_isM3u8Url(_baseItem.source)) return;
    final player = widget.dependencies.playerService;
    _hlsColdTimer = Timer(HlsColdProbe.retryDelay, () async {
      _hlsColdTimer = null;
      if (!mounted) return;
      final result = await HlsColdProbe.probe(
        _baseItem.source,
        maxAttempts: 1,
        log: (stage, {detail}) => _probeHlsResume(player, stage, detail),
      );
      if (!mounted) return;
      if (result.variants.isNotEmpty && _hlsVariants.isEmpty) {
        setState(() => _hlsVariants = result.variants);
      }
    });
  }

  /// Inicia o observador de capacidade: so TV, so Automatica, so
  /// HLS com master. Desktop, MP4 e playlist simples nunca entram.
  void _startHlsObserver() {
    _hlsObserveTimer?.cancel();
    _obsAt = null;
    _obsPos = null;
    if (!_tvMode) return;
    if (_hlsQuality.value != HlsVariants.autoQualityId) return;
    if (_currentItem.sourceType != MediaSourceType.url) return;
    if (!_isM3u8Url(_baseItem.source)) return;
    _hlsObserveTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_observeHlsTick()),
    );
  }

  /// Tick do observador: primeira janela de reproducao real.
  /// Saudavel encerra a observacao; lento desce um degrau uma
  /// vez; sem dados/variantes mantem o que esta tocando.
  Future<void> _observeHlsTick() async {
    if (!mounted || _hlsAutoDowngraded) {
      _hlsObserveTimer?.cancel();
      return;
    }
    if (!_tvMode || _hlsQuality.value != HlsVariants.autoQualityId) {
      _hlsObserveTimer?.cancel();
      return;
    }
    final player = widget.dependencies.playerService;
    final session = player.session;
    if (session.status != PlaybackStatus.playing) {
      _obsAt = null;
      _obsPos = null;
      return;
    }
    final now = _now();
    final startAt = _obsAt;
    final startPos = _obsPos;
    if (startAt == null || startPos == null) {
      _obsAt = now;
      _obsPos = session.position;
      return;
    }
    final wall = now.difference(startAt);
    if (wall < const Duration(seconds: 3)) return;
    final ratio = HlsVariants.playbackRatio(startPos, session.position, wall);
    if (ratio == null) {
      _obsAt = null;
      _obsPos = null;
      return;
    }
    if (ratio >= HlsVariants.observedRatioThreshold) {
      _hlsObserveTimer?.cancel();
      return;
    }
    var variants = _hlsVariants;
    if (variants.isEmpty) {
      variants = await HlsVariants.fetchVariants(_baseItem.source);
      if (!mounted) return;
      if (variants.isNotEmpty) {
        setState(() => _hlsVariants = variants);
      }
    }
    final target = HlsVariants.downgradeUrl(
      masterUrl: _baseItem.source,
      variants: variants,
      currentUrl: _currentItem.source,
      ratio: ratio,
    );
    _hlsObserveTimer?.cancel();
    if (target == null) return;
    _hlsAutoDowngraded = true;
    await _reopenHlsTarget(target, HlsVariants.autoQualityId);
  }

  /// E master HLS de verdade? URL .m3u8 com variantes reais.
  /// Falha de deteccao ou playlist simples: false (fluxo atual).
  Future<bool> _isHlsMaster() async {
    if (_currentItem.sourceType != MediaSourceType.url) return false;
    if (!_isM3u8Url(_baseItem.source)) return false;
    if (_hlsVariants.isNotEmpty) return true;
    final variants = await HlsVariants.fetchVariants(_baseItem.source);
    if (!mounted) return false;
    if (variants.isNotEmpty) {
      setState(() => _hlsVariants = variants);
    }
    return variants.isNotEmpty;
  }

  /// Retomada HLS: a variante ja abriu no caminho normal; aqui so
  /// o seek (falha dele nao derruba a abertura) e o agendamento
  /// da verificacao unica. Tudo que esta sonda registra e leitura:
  /// nenhum seek, seekBy, open ou stop novo.
  /// Prontidão real da retomada: sai de buffering e observa o
  /// primeiro avanço real de posição (prova de demuxer vivo; seek
  /// em demuxer frio morre em silêncio). Timeout limitado: estoura
  /// e o seek sai mesmo assim (melhor esforço, registrado).
  Future<bool> _waitForHlsReady(MediaPlayerService player) async {
    Duration? baseline;
    for (var i = 0; i < HlsVariants.hlsReadyMaxSamples; i++) {
      if (!mounted) return false;
      final session = player.session;
      if (session.status == PlaybackStatus.error ||
          session.status == PlaybackStatus.completed) {
        return false;
      }
      final settled = session.status != PlaybackStatus.loading &&
          session.status != PlaybackStatus.buffering;
      if (settled) {
        final pos = session.position;
        if (baseline != null && pos != baseline) return true;
        baseline ??= pos;
      } else {
        baseline = null;
      }
      await Future.delayed(HlsVariants.hlsReadyPoll);
    }
    return false;
  }

  /// Liga a cobertura do vídeo.
  void _beginReposition(MediaPlayerService player) {
    if (_repositioning) return;
    setState(() => _repositioning = true);
  }

  /// Desliga a cobertura quando a imagem chega perto de [target] (ou
  /// no teto do pouso, ou em erro/fim). Só lê a sessão.
  Future<void> _endRepositionWhenLanded(
      MediaPlayerService player, Duration target) async {
    Duration? landedAt;
    // Teto por contagem (não relógio de parede): verificação + pouso.
    final limit = (HlsVariants.hlsVerifyDelay + HlsVariants.hlsCorrectionSettle)
            .inMilliseconds ~/
        HlsVariants.hlsReadyPoll.inMilliseconds;
    var ticks = 0;
    _repositionTimer?.cancel();
    _repositionTimer = Timer.periodic(HlsVariants.hlsReadyPoll, (timer) {
      ticks++;
      if (!mounted || !_repositioning) {
        timer.cancel();
        return;
      }
      final session = player.session;
      var done = ticks > limit ||
          session.status == PlaybackStatus.error ||
          session.status == PlaybackStatus.completed;
      final settled = session.status != PlaybackStatus.loading &&
          session.status != PlaybackStatus.buffering;
      final near = !HlsVariants.resumeNeedsCorrection(session.position, target);
      // A posição informada pula para o alvo na hora do seek, mas a TV
      // ainda mostra o quadro antigo (título) por um instante: só sai
      // depois de o vídeo ANDAR a partir do ponto salvo.
      if (settled && near) {
        if (landedAt != null && session.position != landedAt) done = true;
        landedAt ??= session.position;
      } else {
        landedAt = null;
      }
      if (done) _endReposition(player);
    });
  }

  void _endReposition(MediaPlayerService player) {
    _repositionTimer?.cancel();
    _repositionTimer = null;
    if (!_repositioning) return;
    if (mounted) setState(() => _repositioning = false);
  }

  Future<void> _resumeHlsMaster(
      MediaPlayerService player, Duration target) async {
    _beginReposition(player);
    final before = player.session;
    _probeHlsResume(
        player,
        'start',
        'id=${_currentItem.id} targetMs=${target.inMilliseconds} '
            'durMs=${before.duration?.inMilliseconds ?? 'none'} '
            'statusBefore=${before.status.name} '
            'effective=${_hlsEffective.value ?? 'master'} '
            'loading=${_isLoadingStatus(before.status)}');
    final ready = await _waitForHlsReady(player);
    if (!mounted) return;
    final readySession = player.session;
    _probeHlsResume(
        player,
        'readiness',
        'ready=$ready status=${readySession.status.name} '
            'posMs=${readySession.position.inMilliseconds}');
    final beforeMs = player.session.position.inMilliseconds;
    final seekAt = _now();
    try {
      await player.seek(target);
    } catch (_) {
      // Seek recusado: a verificacao abaixo e a correcao unica.
    }
    final afterSeek = player.session;
    _probeHlsResume(
        player,
        'seek',
        'at=${seekAt.toIso8601String()} beforeMs=$beforeMs '
            'posAfterMs=${afterSeek.position.inMilliseconds} '
            'status=${afterSeek.status.name} '
            'loading=${_isLoadingStatus(afterSeek.status)}');
    if (!mounted) return;
    unawaited(_endRepositionWhenLanded(player, target));
    _scheduleResumeProbeReadings(player);
    _resumeTimer?.cancel();
    _resumeTimer = Timer(HlsVariants.hlsVerifyDelay, () async {
      _resumeTimer = null;
      if (!mounted) return;
      final session = player.session;
      _probeHlsResume(
          player,
          'verify',
          'posMs=${session.position.inMilliseconds} '
              'status=${session.status.name} '
              'loading=${_isLoadingStatus(session.status)}');
      if (session.status == PlaybackStatus.error ||
          session.status == PlaybackStatus.completed) {
        _probeHlsResume(player, 'correction', 'skipped=status');
        return;
      }
      final duration = session.duration;
      if (duration != null &&
          session.position >= duration - const Duration(seconds: 5)) {
        _probeHlsResume(player, 'correction', 'skipped=near-end');
        return;
      }
      if (!HlsVariants.resumeNeedsCorrection(session.position, target)) {
        _probeHlsResume(player, 'correction', 'skipped=within-tolerance');
        return;
      }
      // No maximo UMA correcao: este timer e de disparo unico e
      // nada reagenda outra tentativa.
      final beforeMs = session.position.inMilliseconds;
      try {
        await player.seek(target);
      } catch (_) {
        // Correcao recusada: segue do ponto real, sem loop.
      }
      _probeHlsResume(
          player,
          'correction',
          'beforeMs=$beforeMs '
              'afterMs=${player.session.position.inMilliseconds} '
              'status=${player.session.status.name}');
      // A correção só vale dentro da tolerância: valida o pouso
      // após estabilizar. Pouso incorreto cai no fallback seguro
      // (pausa + histórico preservado), nunca num loop de seeks.
      await Future.delayed(HlsVariants.hlsCorrectionSettle);
      if (!mounted) return;
      final landed = player.session;
      final within =
          !HlsVariants.resumeNeedsCorrection(landed.position, target);
      _probeHlsResume(player, 'correction-settle',
          'posMs=${landed.position.inMilliseconds} within=$within');
      if (within) return;
      try {
        await player.pause();
      } catch (_) {
        // Pausa best-effort: a proteção abaixo vale de todo jeito.
      }
      if (!mounted) return;
      _hlsPositionProtect = true;
      _probeHlsResume(
          player,
          'fallback',
          'reason=landing-unverified '
              'targetMs=${target.inMilliseconds} '
              'posMs=${player.session.position.inMilliseconds} '
              'effective=${_hlsEffective.value ?? 'master'}');
    });
  }

  static bool _isLoadingStatus(PlaybackStatus status) =>
      status == PlaybackStatus.loading || status == PlaybackStatus.buffering;

  /// Leituras agendadas da sonda (500 ms, 1 s, 1,5 s): só leem a
  /// sessão e registram; nunca disparam seeks.
  void _scheduleResumeProbeReadings(MediaPlayerService player) {
    _resumeProbeTimer?.cancel();
    var ticks = 0;
    _resumeProbeTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      ticks++;
      if (!mounted || ticks > 3) {
        timer.cancel();
        if (identical(_resumeProbeTimer, timer)) _resumeProbeTimer = null;
        return;
      }
      final session = player.session;
      _probeHlsResume(
          player,
          'reading',
          'atMs=${ticks * 500} posMs=${session.position.inMilliseconds} '
              'status=${session.status.name} '
              'loading=${_isLoadingStatus(session.status)}');
    });
  }

  /// Registra a sonda no log técnico local (quando o motor é o
  /// supervisionado) e no logcat em debug. Só números, estados, o
  /// id do item e o rótulo da variante — nunca URL ou segredo.
  void _probeHlsResume(MediaPlayerService player, String stage,
      [String? detail]) {
    final inner = player is SupervisedPlayerService
        ? player
        : widget.dependencies.playerService is SupervisedPlayerService
            ? widget.dependencies.playerService as SupervisedPlayerService
            : null;
    inner?.logResumeProbe(stage, detail: detail);
    assert(() {
      debugPrint('[hls-resume] $stage ${detail ?? ''}');
      return true;
    }());
  }

  /// Espera a duracao chegar (mpv com arquivo conhecido) antes do seek
  /// de retomada. Retorna de imediato se ja houver duracao; timeout
  /// silencioso para nao travar arquivo quebrado.
  Future<void> _waitForDuration(
      MediaPlayerService player, Duration timeout) async {
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
          final pausedReady = s.status == PlaybackStatus.paused && dur != null;
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
    WidgetsBinding.instance.removeObserver(this);
    _minimizedSub?.cancel();
    _seekFlashTimer?.cancel();
    _repositionTimer?.cancel();
    // Saiu do player em tela cheia no celular: devolve barras e giro.
    if (_mobile && _fullscreen) unawaited(_chrome.setFullscreen(false));
    widget.dependencies.windowService.removeBeforeClose(_saveOnWindowClose);
    _chrome.cancelAutoHide();
    _resumeTimer?.cancel();
    _resumeProbeTimer?.cancel();
    _hlsObserveTimer?.cancel();
    _hlsColdTimer?.cancel();
    _hlsColdTimer = null;
    _subscription?.cancel();
    _systemVolumeSub?.cancel();
    _screenFocus.dispose();
    _sourceQuality.dispose();
    _hlsQuality.dispose();
    _hlsEffective.dispose();
    _controlsScope.dispose();
    _cornerScope.dispose();
    _overlayPrimaryFocus.dispose();
    super.dispose();
  }

  /// App oculto (`hidden`) ou em segundo plano (`paused`): grava a
  /// posicao sem pausar. O video segue tocando no minimizado e, se o
  /// app for encerrado la, a retomada nao se perde. No Windows o
  /// minimizar chega por [WindowService.minimized] (ver initState).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_saveSession(pause: false));
    }
  }

  /// Overlay modal de erro ou fim de video no ar (spec 11, 17).
  bool get _overlayUp =>
      _session.status == PlaybackStatus.error ||
      _session.status == PlaybackStatus.completed;

  @override
  Widget build(BuildContext context) {
    final next = _nextItem;
    // Margem segura anti-overscan na TV (spec 27.5); 16 no desktop e
    // 8 na janela baixa.
    _dense = !_tvMode &&
        MediaQuery.sizeOf(context).height < PlayerControls.denseMaxHeight;
    _mobile = !_tvMode && MobileMode.of(context);
    final edge = TvLayout.isTv(context)
        ? TvLayout.safeMarginOf(context)
        : (_dense ? 8.0 : 16.0);
    // Toda saida pela navegacao (X dos cantos, gesto, voltar do
    // sistema/TV, Q) passa por aqui: salva a sessao antes de fechar
    // (spec 11, 19). O Esc passa pelo _onBack e cai aqui no fim.
    // F2 (Fase 4b): overlay modal abriu. O autofocus sozinho nao
    // transfere o foco quando ele esta no no da tela (barra oculta
    // antes do fim/erro); reivindica o no primario explicito.
    final modalUp = _overlayUp || _replayOffer;
    if (modalUp && !_wasOverlayUp) {
      _wasOverlayUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && modalUp) _overlayPrimaryFocus.requestFocus();
      });
    } else if (!modalUp) {
      _wasOverlayUp = false;
    }
    // A tela assina o chrome (ADR-0002): qualquer mudança no módulo
    // reconstrói via ListenableBuilder, sem cópia local de estado.
    return ListenableBuilder(
      listenable: _chrome,
      builder: (context, _) => PopScope(
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
        // TV: com a barra visivel, o primeiro BACK so a esconde; o
        // segundo sai salvando. X/Fechar/Q saem direto (_exitPlayer).
        if (_tvMode && _controlsVisible && !_overlayUp && !_exitRequested) {
          _hideControls();
          return;
        }
        _exitRequested = false;
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
                    // Celular: toque alterna os controles. Desktop segue
                    // com o clique so reexibindo.
                    onTap: _mobile ? _toggleControlsByTouch : _poke,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Toque duplo (celular) so no video: nos botoes ele
                        // seguraria cada toque 300 ms. Com aviso na tela
                        // (erro, fim, Ver de novo) desliga pelo mesmo motivo.
                        GestureDetector(
                          onDoubleTapDown: _mobile && !modalUp
                              ? (d) => _doubleTapAt = d.localPosition
                              : null,
                          onDoubleTap:
                              _mobile && !modalUp ? _seekByDoubleTap : null,
                          child: _VideoArea(
                            player: widget.dependencies.playerService,
                            session: _session,
                            isLocal: _currentItem.sourceType ==
                                MediaSourceType.local,
                            onRetry: _open,
                            onCancel: () =>
                                widget.dependencies.playerService.stop(),
                            onRelocate: _relocate,
                            onRemoveFromLibrary: _removeFromLibrary,
                            onEditLink: _editLink,
                            onReplay: _replay,
                            isFavorite: _isFavorite,
                            onToggleFavorite: _toggleFavorite,
                            nextTitle: next?.title,
                            onPlayNext:
                                next == null ? null : () => _playNext(next),
                            onClose: _exitPlayer,
                            onBackToAutomatic: _hlsVariants.isNotEmpty &&
                                    _hlsQuality.value !=
                                        HlsVariants.autoQualityId
                                ? () =>
                                    _switchHlsQuality(HlsVariants.autoQualityId)
                                : null,
                            primaryFocus: _overlayPrimaryFocus,
                            showReplayOffer: _replayOffer &&
                                _session.status != PlaybackStatus.error &&
                                _session.status != PlaybackStatus.completed,
                            onWatchAgain: () {
                              setState(() => _replayOffer = false);
                              unawaited(_replay());
                            },
                            onDismissReplay: () =>
                                setState(() => _replayOffer = false),
                          ),
                        ),
                        if (_repositioning) const _RepositionCover(),
                        if (_seekFlash != null)
                          _SeekFlash(label: _seekFlash!, left: _seekFlashLeft),
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
                                excluding: !_controlsVisible || _cinema,
                                child: FocusScope(
                                  node: _cornerScope,
                                  child: _TvCornerIcons(
                                    tvMode: _tvMode,
                                    child: Row(
                                      children: [
                                        RoundPlayerButton(
                                          tooltip: _fullscreen
                                              ? 'Sair da tela cheia'
                                              : 'Tela cheia',
                                          icon: _fullscreen
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                          size: _cornerSize,
                                          padding: _cornerPadding,
                                          overVideo: true,
                                          onPressed: _toggleFullscreen,
                                        ),
                                        const Spacer(),
                                        RoundPlayerButton(
                                          tooltip: 'Modo cinema',
                                          icon: Icons.theaters_outlined,
                                          size: _cornerSize,
                                          padding: _cornerPadding,
                                          overVideo: true,
                                          onPressed: _toggleCinema,
                                        ),
                                        // Compacto e janela do desktop: no
                                        // celular nao ha janela a encolher.
                                        if (!_mobile)
                                          RoundPlayerButton(
                                            tooltip: _compact
                                                ? 'Sair do modo compacto'
                                                : 'Modo compacto',
                                            icon: Icons
                                                .picture_in_picture_alt_outlined,
                                            size: _cornerSize,
                                            padding: _cornerPadding,
                                            overVideo: true,
                                            onPressed: _toggleCompact,
                                          ),
                                        RoundPlayerButton(
                                          tooltip: _isFavorite
                                              ? 'Remover dos favoritos'
                                              : 'Adicionar aos favoritos',
                                          icon: _isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_outline,
                                          size: _cornerSize,
                                          padding: _cornerPadding,
                                          overVideo: true,
                                          onPressed: _toggleFavorite,
                                        ),
                                        RoundPlayerButton(
                                          tooltip: 'Fechar',
                                          icon: Icons.close,
                                          size: _cornerSize,
                                          padding: _cornerPadding,
                                          overVideo: true,
                                          onPressed: _exitPlayer,
                                        ),
                                      ],
                                    ),
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
                                      constraints:
                                          const BoxConstraints(maxWidth: 880),
                                      child: _tvMode
                                          ? TvPlayerControls(
                                              player: widget
                                                  .dependencies.playerService,
                                              session: _session,
                                              videoTitle: _currentItem.title,
                                              settingsKey: _settingsKey,
                                              systemMuted: _systemSilent,
                                              onOpenPanel: (view, anchor) =>
                                                  _openSettings(anchor,
                                                      view: view),
                                            )
                                          : PlayerControls(
                                              player: widget
                                                  .dependencies.playerService,
                                              session: _session,
                                              onOpenSettings: _openSettings,
                                              videoTitle: _currentItem.title,
                                              settingsKey: _settingsKey,
                                              dense: _dense,
                                              systemMuted: _systemSilent,
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
    // Tecla física de volume (VOL+/VOL− do controle da TV, botões do
    // celular, teclado multimídia): se o app estava mudado, despluga
    // o mudo em qualquer estado da barra. Retorna false de propósito
    // para o sistema ajustar o próprio volume — o app nunca consome
    // essa tecla.
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      final context = _screenFocus.context;
      if (context != null &&
          ModalRoute.of(context)?.isCurrent == true &&
          !_panelOpen &&
          !_overlayUp &&
          _session.isMuted) {
        widget.dependencies.playerService.setMuted(false);
      }
      return false;
    }
    if (_controlsVisible && !_panelOpen && !_overlayUp) {
      // Navegando na barra visivel (controle remoto ou teclado): a tecla
      // segue para o foco normal e so rearma o auto-hide (spec 12.2).
      final current = _screenFocus.context;
      if (current != null && ModalRoute.of(current)?.isCurrent == true) {
        _chrome.pokeControls();
      }
      return false;
    }
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
      case LogicalKeyboardKey.arrowDown:
        // Volume interno só no desktop/Windows: no celular vale o
        // volume do sistema e na TV o da TV (VOL+/VOL− do controle
        // remoto, fora do app). Nessas plataformas as setas só
        // reexibem; busca segue nas laterais e o foco e a navegação
        // valem com a barra visível. No desktop, a seta oculta
        // ajusta o volume interno e persiste como inicial.
        if (!_tvMode && !_isMobileOs) {
          _stepVolume(event.logicalKey == LogicalKeyboardKey.arrowUp ? 1 : -1);
        }
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
        if (!_panelOpen) _exitPlayer();
      },
    };
  }

  void _poke() {
    final wasHidden = !_controlsVisible;
    _chrome.pokeControls();
    // Reexibir depois de oculto: o foco morreu com a barra, ancora de
    // novo num controle (sem roubar o foco de quem ja tem um valido,
    // ex. mouse sobre a barra apos Tab).
    if (wasHidden) _restoreFocusIfLost();
  }

  /// Esconde a barra e os cantos (auto-hide e primeiro BACK na TV).
  /// O estado vive no módulo; o foco continua local.
  void _hideControls() {
    _chrome.hideControls();
    _anchorFocusOnHide();
  }

  /// Ancora o foco ao ocultar: guarda o último foco da barra e ancora
  /// na raiz. Sem isso o foco cai no escopo da rota e a primeira seta
  /// do D-pad se perde. Com overlay modal, nao rouba: o autofocus do
  /// botao primario vale (F2, Fase 4b).
  void _anchorFocusOnHide() {
    final current = FocusManager.instance.primaryFocus;
    // focusedChild e grudento (ultimo, nao atual): so guarda com o
    // foco DENTRO da barra; fora dela, null pede o proximo da ordem.
    _lastControlFocus =
        current != null && current.ancestors.contains(_controlsScope)
            ? current
            : null;
    // Ancorar no no da tela: sem isso o foco cai no escopo da rota
    // e a primeira seta do D-pad se perde. Com overlay modal, nao
    // rouba: o autofocus do botao primario vale (F2, Fase 4b).
    if (!_overlayUp) _screenFocus.requestFocus();
  }

  /// Saida pedida de proposito (X, Fechar do overlay, Q): sai salvando
  /// direto, sem o passo "BACK esconde a barra" da TV.
  void _exitPlayer() {
    _exitRequested = true;
    Navigator.of(context).maybePop();
  }

  /// Devolve o foco a um controle quando ele se perdeu (card ocultado
  /// e reexibido, overlay fechado, cantos ocultos). So age quando o
  /// foco atual e nulo, o no raiz ou sem contexto: nunca rouba um foco
  /// valido. Pos-frame porque a arvore-alvo pode estar remontando.
  void _restoreFocusIfLost() {
    final current = FocusManager.instance.primaryFocus;
    final lost =
        current == null || current == _screenFocus || current.context == null;
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

  /// Setas ocultas no desktop/Windows: o volume escolhido vira o
  /// volume inicial da preferencia e o proximo player abre com ele
  /// (único ajuste fino interno; sem trilho em nenhuma plataforma).
  void _persistVolume(double volume) {
    final prefs = widget.dependencies.preferencesService;
    unawaited(prefs.update(prefs.current.copyWith(initialVolume: volume)));
  }

  /// Setas com controles ocultos no desktop/Windows: passo de 0,05,
  /// salvo como volume inicial. No celular e na TV nunca chega aqui.
  void _stepVolume(int direction) {
    final next = steppedVolume(_session.volume, direction);
    widget.dependencies.playerService.setVolume(next);
    _persistVolume(next);
  }

  /// Toque no video (celular): oculta se visivel, reexibe se oculto.
  /// A condição (sem painel/overlay) vive no guard do módulo.
  void _toggleControlsByTouch() {
    _chrome.toggleControls();
  }

  /// Toque duplo (celular): metade esquerda volta, direita avanca.
  void _seekByDoubleTap() {
    final at = _doubleTapAt;
    if (at == null || _overlayUp) return;
    final width = MediaQuery.sizeOf(context).width;
    final back = at.dx < width / 2;
    final player = widget.dependencies.playerService;
    player.seekBy(back ? -AppConstants.seekStep : AppConstants.seekStep);
    final seconds = AppConstants.seekStep.inSeconds;
    _seekFlashTimer?.cancel();
    setState(() {
      _seekFlash = back ? '-$seconds s' : '+$seconds s';
      _seekFlashLeft = back;
    });
    _seekFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    await widget.dependencies.windowService.setFullscreen(next);
    if (_mobile) {
      await _chrome.setFullscreen(next);
    }
    if (!mounted) return;
    _chrome.pokeControls();
    setState(() {
      // Só fora do mobile o estado é espelho local (desktop/TV);
      // no mobile ele já vive no módulo (assinatura acima).
      if (!_mobile) _windowFullscreen = next;
    });
    // Os cantos ocultam/exibem: o foco pode ter morrido com eles.
    // Ancorar no no raiz mataria as setas (nada fora de um retangulo
    // de tela cheia), entao restaura num controle de verdade.
    _restoreFocusIfLost();
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
    // Variantes HLS sob demanda: na classe tetada a abertura ja
    // buscou; nas demais, buscar ao abrir Opcoes nao muda a
    // abertura (desktop segue abrindo o master sem fetch).
    if (_hlsVariants.isEmpty &&
        _currentItem.sourceType == MediaSourceType.url &&
        _isM3u8Url(_baseItem.source)) {
      final variants = await HlsVariants.fetchVariants(_baseItem.source);
      if (!mounted) return;
      if (variants.isNotEmpty) {
        setState(() => _hlsVariants = variants);
      }
    }
    setState(() {
      _panelOpen = true;
    });
    _chrome.showControls();
    final prefs = widget.dependencies.preferencesService.current;
    final animations = prefs.animations;
    if (!context.mounted) return;
    await PlayerSettingsPanel.show(
      context,
      anchorContext: anchorContext,
      player: widget.dependencies.playerService,
      session: _session,
      videoTitle: _currentItem.title,
      preferredAudio: prefs.defaultAudio,
      preferredSubtitle: prefs.defaultSubtitle,
      sourceLabel: sourceLabelFor(_currentItem),
      sourceQualities: decodeSourceQualities(_baseItem.metadata['qualities']),
      selectedSourceQualityId: _sourceQuality.value,
      sourceQualityListenable: _sourceQuality,
      onSelectSourceQuality: _switchSourceQuality,
      hlsQualities: _hlsOptions,
      selectedHlsQualityId: _hlsQuality.value,
      hlsQualityListenable: _hlsQuality,
      onSelectHlsQuality: _switchHlsQuality,
      effectiveHlsLabel: _hlsEffective.value,
      effectiveHlsListenable: _hlsEffective,
      initialView: view,
      transitionDuration:
          animations ? AppConstants.shortTransition : Duration.zero,
    );
    if (mounted) {
      setState(() => _panelOpen = false);
      _chrome.pokeControls();
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
    final qualities = decodeSourceQualities(_baseItem.metadata['qualities']);
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
    final entry = widget.dependencies.historyService.latestFor(next.id);
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
    await widget.dependencies.libraryService.toggleFavorite(_currentItem.id);
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
      _hlsQuality.value = HlsVariants.autoQualityId;
      _hlsVariants = const [];
      _hlsEffective.value = null;
      _hlsAutoDowngraded = false;
      _hlsObserveTimer?.cancel();
      _hlsPositionProtect = false;
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
      message:
          "'${_currentItem.title}' sai da biblioteca e do histórico. O arquivo original não é apagado.",
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
  /// [pause] falso so grava (minimizar): a reproducao continua.
  Future<void> _saveSession({bool pause = true}) async {
    // Posição HLS não verificada (retomada ou troca): nunca marca
    // concluído nem sobrescreve o histórico com o ponto errado —
    // só pausa e mantém o ponto salvo anterior.
    if (_hlsPositionProtect) {
      final kept =
          widget.dependencies.historyService.latestFor(_currentItem.id);
      _probeHlsResume(
          widget.dependencies.playerService,
          'history-protect',
          'keptMs=${kept?.position?.inMilliseconds ?? 'none'} '
              'completed=${kept?.completed ?? 'none'}');
      if (pause) await widget.dependencies.playerService.pause();
      return;
    }
    // Le o motor (fresco), nao o espelho: no BACK o evento de erro pode
    // ainda nao ter chegado ao listener do widget.
    final live = widget.dependencies.playerService.session;
    final position = live.position;
    final duration = live.duration;
    // Sem informacao nova nao sobrescreve retomada anterior: sair com
    // erro ou antes do primeiro frame apagaria o ponto salvo (TV).
    final prior = _currentItem.lastPosition;
    // Replay de concluido: a base do progresso e o zero, nao o fim salvo.
    final base = _openedCompleted ? Duration.zero : prior;
    final hadResume = prior != null && prior > Duration.zero;
    final hasProgress =
        position > Duration.zero || (duration != null && position != base);
    if (widget.dependencies.preferencesService.current.rememberPosition &&
        (hasProgress || !hadResume)) {
      final history = widget.dependencies.historyService;
      final library = widget.dependencies.libraryService;
      final completed = AppConstants.isCompletedPosition(
          position: position, duration: duration);
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
    if (pause) await widget.dependencies.playerService.pause();
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
    this.showReplayOffer = false,
    this.onWatchAgain,
    this.onDismissReplay,
    this.onBackToAutomatic,
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

  /// Volta para a qualidade Automatica (falha de variante HLS
  /// manual). Null esconde a acao.
  final VoidCallback? onBackToAutomatic;
  final FocusNode primaryFocus;

  /// Oferta "Ver de novo" (reabertura de concluido, spec 11): mostra
  /// o card com as acoes abaixo. Null nas acoes esconde a oferta.
  final bool showReplayOffer;
  final VoidCallback? onWatchAgain;
  final VoidCallback? onDismissReplay;

  /// Mensagem pelo TIPO do erro, nunca a string nativa (pode conter
  /// caminhos e URLs). Cada tipo diz de quem e a culpa: rede, fonte,
  /// decodificador ou tempo esgotado — nunca o player por um erro da
  /// fonte (spec 26).
  /// Card da oferta "Ver de novo" (reabertura de concluido, spec 11):
  /// mesmo visual do card de fim de video (fundo solido do painel,
  /// tipografia e raio por modo), so com as acoes da reabertura.
  Widget _replayOfferCard(BuildContext context) {
    final isTv = TvLayout.isTv(context);
    final tokens = isTv ? TvLayout.tokensOf(context) : null;
    return Center(
      child: Container(
        padding: isTv
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: PlayerSettingsPanel.panelColor,
          borderRadius: BorderRadius.circular(isTv ? tokens!.panelRadius : 12),
          border: isTv
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Você já concluiu este vídeo',
                style: isTv
                    ? TextStyle(
                        color: PlayerTheme.primaryText,
                        fontSize: tokens!.textBody,
                        fontWeight: FontWeight.w600,
                      )
                    : const TextStyle(color: PlayerTheme.primaryText)),
            const SizedBox(height: 4),
            Text('Começa do início.',
                style: isTv
                    ? TextStyle(
                        color: PlayerTheme.secondaryText,
                        fontSize: tokens!.textCaption,
                      )
                    : const TextStyle(color: PlayerTheme.secondaryText)),
            SizedBox(height: isTv ? 8 : 12),
            Wrap(
              spacing: isTv ? 8 : 12,
              runSpacing: isTv ? 8 : 12,
              alignment: WrapAlignment.center,
              children: [
                FocusableButton(
                  label: 'Ver de novo',
                  focusNode: primaryFocus,
                  icon: Icons.replay,
                  primary: true,
                  autofocus: true,
                  onPressed: onWatchAgain!,
                ),
                FocusableButton(
                  label: 'Fechar',
                  icon: Icons.close,
                  onPressed: onDismissReplay!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
      PlaybackErrorKind.decoder => const MediaError.incompatible().message,
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
          if (onBackToAutomatic != null)
            FocusableButton(
              label: 'Voltar para Automática',
              icon: Icons.tune,
              onPressed: onBackToAutomatic!,
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
                // Cancelar so na abertura: no meio do video (seek,
                // pausa) o buffering e passageiro e o botao parava a
                // reproducao; travamento longo vira erro pelo
                // supervisor, com "Tentar novamente".
                if (session.status == PlaybackStatus.loading ||
                    session.position <= Duration.zero) ...[
                  const SizedBox(height: 16),
                  FocusableButton(
                    label: 'Cancelar',
                    icon: Icons.close,
                    onPressed: onCancel,
                  ),
                ],
              ],
            ),
          ),
        if (showReplayOffer && onWatchAgain != null && onDismissReplay != null)
          _replayOfferCard(context),
        if (session.status == PlaybackStatus.completed)
          Builder(
            builder: (context) {
              // Card solido na cor do painel de Opcoes, nos dois
              // modos: o preto 0.7 deixava o video atravessar e sumia
              // com os botoes (blur e so na barra do player). Na TV,
              // tipografia, respiros e raio seguem os tokens compactos
              // e os botoes ja usam o alvo minimo dos tokens via
              // FocusableButton. No desktop, so a cor muda: dimensoes
              // intactas, pixel a pixel.
              final isTv = TvLayout.isTv(context);
              final tokens = isTv ? TvLayout.tokensOf(context) : null;
              return Center(
                child: Container(
                  padding: isTv
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                      : const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: PlayerSettingsPanel.panelColor,
                    borderRadius:
                        BorderRadius.circular(isTv ? tokens!.panelRadius : 12),
                    border: isTv
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.08))
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Reprodução concluída',
                          style: isTv
                              ? TextStyle(
                                  color: PlayerTheme.primaryText,
                                  fontSize: tokens!.textBody,
                                  fontWeight: FontWeight.w600,
                                )
                              : const TextStyle(
                                  color: PlayerTheme.primaryText)),
                      if (nextTitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'A seguir: $nextTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isTv
                              ? TextStyle(
                                  color: PlayerTheme.secondaryText,
                                  fontSize: tokens!.textCaption,
                                )
                              : const TextStyle(
                                  color: PlayerTheme.secondaryText),
                        ),
                      ],
                      SizedBox(height: isTv ? 8 : 12),
                      Wrap(
                        spacing: isTv ? 8 : 12,
                        runSpacing: isTv ? 8 : 12,
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
              );
            },
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
  FocusNode? _nearestIn(FocusScopeNode scope, FocusNode current,
      {required bool above}) {
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

/// Glifos dos cantos: 20 na TV (como a barra), tema no desktop.
class _TvCornerIcons extends StatelessWidget {
  const _TvCornerIcons({required this.tvMode, required this.child});

  final bool tvMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!tvMode) return child;
    return IconTheme(
      data: const IconThemeData(size: 20),
      child: child,
    );
  }
}

/// Rotulo do toque duplo no celular ("-10 s" a esquerda, "+10 s" a
/// direita). So desenha: nao recebe toques.
class _SeekFlash extends StatelessWidget {
  const _SeekFlash({required this.label, required this.left});

  final String label;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: left ? const Alignment(-0.6, 0) : const Alignment(0.6, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cobre o vídeo enquanto a retomada/troca de qualidade leva a imagem
/// ao ponto salvo (o início do vídeo não aparece). Não recebe toques:
/// os controles continuam por cima.
class _RepositionCover extends StatelessWidget {
  const _RepositionCover();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sem animação de propósito: a cobertura dura ~1-3 s e um
              // indicador animado não deixaria a tela "assentar".
              const Icon(Icons.update, size: 32),
              const SizedBox(height: 12),
              Text(
                'Ajustando a posição…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
