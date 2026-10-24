import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:player/app/tv_layout.dart';
import 'package:flutter/services.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/player_panel_options.dart';

/// Painel flutuante de configuracoes do player (spec 13), no espirito do
/// Showtime: compacto, ancorado sobre a barra de controles, com relevo e
/// submenus internos (idioma, legendas, repeticao) em vez de lista longa.
/// Abre sem interromper a reproducao e nao exibe como ativas as opcoes
/// indisponiveis.
class PlayerSettingsPanel extends StatefulWidget {
  const PlayerSettingsPanel({
    super.key,
    required this.player,
    required this.session,
    this.videoTitle,
    this.preferredAudio,
    this.preferredSubtitle,
    this.sourceLabel,
    this.source,
    this.hls,
    this.initialView = PlayerPanelView.main,
    this.transitionDuration = AppConstants.shortTransition,
    this.maxHeight,
  });

  final MediaPlayerService player;

  /// Sessao inicial; atualizacoes chegam pelo stream do player.
  final PlaybackSession session;
  final String? videoTitle;

  /// Cluster da fonte (5C). Null = sem secao de rendicao.
  final SourceOptions? source;

  /// Cluster do HLS. Null = sem secao HLS.
  final HlsOptions? hls;

  /// Idiomas preferidos (codigos, ex. "por"): quando nenhuma faixa
  /// casa, o submenu informa ("sem faixa em portugues", spec 26.12).
  final String? preferredAudio;
  final String? preferredSubtitle;

  /// Proveniencia exibida nas informacoes ("Arquivo local", add-on...).
  final String? sourceLabel;

  /// Altura maxima do corpo, calculada pelo [show] a partir da
  /// ancora (TV). Null = sem teto (desktop).
  final double? maxHeight;

  /// Subview aberta de inicio (atalhos I/S/A abrem direto nela, spec 12.3).
  final PlayerPanelView initialView;

  /// Duracao da transicao de abertura e da troca de submenus. Zero com a
  /// preferencia de animacoes desligada (spec 16).
  final Duration transitionDuration;

  /// Cor de fundo do painel e da seta que aponta para o botao.
  static const panelColor = Color(0xFF232326);

  /// Abre o painel ancorado acima do botao clicado (padrao geral de menus,
  /// spec 3.5), centralizado no icone com uma seta apontando para ele.
  /// Fecha tocando fora, com Escape/voltar ou em Fechar.
  /// A sessao e ao vivo: faixas que chegarem depois da abertura (comum no
  /// inicio da midia) aparecem sem reabrir o painel.
  static Future<void> show(
    BuildContext context, {
    required MediaPlayerService player,
    required PlaybackSession session,
    String? videoTitle,
    String? preferredAudio,
    String? preferredSubtitle,
    String? sourceLabel,
    SourceOptions? source,
    HlsOptions? hls,
    BuildContext? anchorContext,
    PlayerPanelView initialView = PlayerPanelView.main,
    Duration transitionDuration = AppConstants.shortTransition,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar configurações',
      barrierColor: Colors.black45,
      transitionDuration: transitionDuration,
      pageBuilder: (dialogContext, _, ___) {
        final screen = MediaQuery.of(dialogContext).size;
        const panelMaxWidth = 340.0;
        const margin = 16.0;
        const gap = 10.0;
        final panelWidth = math.min(panelMaxWidth, screen.width - margin * 2);
        // Ancora: centro horizontal do botao e seu topo. Sem ancora
        // valida, cai no canto inferior direito.
        var anchorX = screen.width - margin - panelWidth / 2;
        var anchorTop = screen.height - margin - 56.0;
        var anchored = false;
        final target = anchorContext?.findRenderObject();
        if (target is RenderBox && target.hasSize) {
          final topLeft = target.localToGlobal(Offset.zero);
          anchorX = topLeft.dx + target.size.width / 2;
          anchorTop = topLeft.dy;
          anchored = true;
        }
        final left = (anchorX - panelWidth / 2)
            .clamp(margin, screen.width - margin - panelWidth)
            .toDouble();
        final caretX =
            anchorX.clamp(left + 14.0, left + panelWidth - 14.0).toDouble();
        // Teto na TV: acima da ancora cabem os cantos (40) + a margem
        // segura (~27) + folga; o resto e do painel. Na TCL (ancora em
        // ~456) = ~384. No desktop, null (sem mudanca).
        // Fora da TV, so em tela baixa (celular deitado, janela pequena
        // do Windows): o painel crescia para cima da engrenagem e saia
        // pelo topo, cortando Idioma/Legendas. Com teto, rola. Com
        // espaco de sobra (>= 480 acima da engrenagem), null como antes.
        final room = anchorTop -
            gap -
            MediaQuery.paddingOf(dialogContext).top -
            margin;
        final cap = TvLayout.isTv(context) && anchored
            ? (anchorTop - 72.0).clamp(200.0, 600.0).toDouble()
            : (anchored && room < shortRoom
                ? math.max(room, 120.0)
                : null);
        return Stack(
          children: [
            Positioned(
              left: left,
              width: panelWidth,
              bottom: screen.height - anchorTop + gap,
              // Escape fecha o painel: a rota do dialogo nao herda os
              // atalhos da tela do player, entao o painel trata o seu
              // proprio (spec 13).
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      Navigator.of(dialogContext).pop(),
                },
                child: PlayerSettingsPanel(
                  player: player,
                  session: session,
                  videoTitle: videoTitle,
                  preferredAudio: preferredAudio,
                  preferredSubtitle: preferredSubtitle,
                  sourceLabel: sourceLabel,
                  source: source,
                  hls: hls,
                  initialView: initialView,
                  transitionDuration: transitionDuration,
                  maxHeight: cap,
                ),
              ),
            ),
            if (anchored)
              Positioned(
                left: caretX - 8,
                top: anchorTop - gap,
                width: 16,
                height: 8,
                child: CustomPaint(painter: _CaretPainter()),
              ),
          ],
        );
      },
    );
  }

  /// Espaco acima da engrenagem abaixo do qual o painel ganha teto e
  /// rola (fora da TV). O painel principal tem ~385 de altura.
  static const shortRoom = 480.0;

  @override
  State<PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

/// Subviews do painel. Publico para que a tela do player abra o painel
/// direto numa delas (atalhos I/S/A, spec 12.3).
enum PlayerPanelView { main, audio, subtitles, quality, repeat, info }

/// Casca estavel: guarda a subview atual enquanto a sessao atualiza abaixo
/// via stream (senao cada tick de posicao expulsaria o usuario do submenu).
class _PlayerSettingsPanelState extends State<PlayerSettingsPanel> {
  late PlayerPanelView _view;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    widget.source?.selectedListenable?.addListener(_onQualityChanged);
    widget.hls?.selectedListenable?.addListener(_onQualityChanged);
    widget.hls?.effectiveListenable?.addListener(_onQualityChanged);
  }

  @override
  void didUpdateWidget(PlayerSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source?.selectedListenable != widget.source?.selectedListenable) {
      oldWidget.source?.selectedListenable?.removeListener(_onQualityChanged);
      widget.source?.selectedListenable?.addListener(_onQualityChanged);
    }
    if (oldWidget.hls?.selectedListenable != widget.hls?.selectedListenable) {
      oldWidget.hls?.selectedListenable?.removeListener(_onQualityChanged);
      widget.hls?.selectedListenable?.addListener(_onQualityChanged);
    }
    if (oldWidget.hls?.effectiveListenable !=
        widget.hls?.effectiveListenable) {
      oldWidget.hls?.effectiveListenable?.removeListener(_onQualityChanged);
      widget.hls?.effectiveListenable?.addListener(_onQualityChanged);
    }
  }

  @override
  void dispose() {
    widget.source?.selectedListenable?.removeListener(_onQualityChanged);
    widget.hls?.selectedListenable?.removeListener(_onQualityChanged);
    widget.hls?.effectiveListenable?.removeListener(_onQualityChanged);
    super.dispose();
  }

  void _onQualityChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tiles = ListTileTheme.of(context);
    final base = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Theme(
        // Na TV, densidade vertical minima: o piso de 48 do ListTile
        // denso cai e as linhas ficam em ~36. No desktop, a densidade
        // do tema (pixel a pixel).
        data: PlayerTheme.playerSurface(base).copyWith(
          visualDensity: TvLayout.isTv(context)
              ? const VisualDensity(vertical: -4)
              : base.visualDensity,
        ),
        child: ListTileTheme(
          // Linhas confortaveis na TV: respiro do desktop (4) com a
          // densidade minima, para o painel caber folgado acima da
          // barra. No desktop, o proprio tema (pixel a pixel).
          data: TvLayout.isTv(context)
              ? tiles.copyWith(
                  minVerticalPadding: 3,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                )
              : tiles,
          child: Material(
            color: PlayerSettingsPanel.panelColor,
            elevation: 12,
            shadowColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<PlaybackSession>(
              stream: widget.player.sessionStream,
              initialData: widget.session,
              builder: (context, snapshot) => _PanelBody(
                player: widget.player,
                session: snapshot.data ?? widget.session,
                videoTitle: widget.videoTitle,
                preferredAudio: widget.preferredAudio,
                preferredSubtitle: widget.preferredSubtitle,
                sourceLabel: widget.sourceLabel,
                source: widget.source,
                hls: widget.hls,
                view: _view,
                onViewChanged: (view) => setState(() => _view = view),
                transitionDuration: widget.transitionDuration,
                maxHeight: widget.maxHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.player,
    required this.session,
    required this.view,
    required this.onViewChanged,
    required this.transitionDuration,
    this.videoTitle,
    this.preferredAudio,
    this.preferredSubtitle,
    this.sourceLabel,
    this.source,
    this.hls,
    this.maxHeight,
  });

  final MediaPlayerService player;
  final PlaybackSession session;
  final String? videoTitle;
  final String? preferredAudio;
  final String? preferredSubtitle;
  final String? sourceLabel;
  final SourceOptions? source;
  final HlsOptions? hls;
  final PlayerPanelView view;
  final ValueChanged<PlayerPanelView> onViewChanged;
  final Duration transitionDuration;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedSwitcher(
      duration: transitionDuration,
      child: switch (view) {
        PlayerPanelView.main => _mainView(context),
        PlayerPanelView.audio => _trackSubView(
            context,
            title: 'Idioma',
            tracks: session.audioTracks,
            selectedId: session.selectedAudioId,
            emptyLabel: 'Nenhuma faixa disponível',
            preferredLanguage: preferredAudio,
            // Lista de audio nunca oferece null: so faixas reais.
            onSelect: (id) => player.selectAudio(id!),
          ),
        PlayerPanelView.subtitles => _trackSubView(
            context,
            title: 'Legendas',
            tracks: session.subtitleTracks,
            selectedId: session.selectedSubtitleId,
            emptyLabel: 'Nenhuma legenda disponível',
            preferredLanguage: preferredSubtitle,
            allowNone: true,
            noneLabel: 'Desativadas',
            onSelect: player.selectSubtitle,
          ),
        PlayerPanelView.quality => _qualitySubView(context),
        PlayerPanelView.repeat => _repeatSubView(context),
        PlayerPanelView.info => _infoSubView(context),
      },
    );
    final cap = maxHeight;
    // Com teto (TV via show): o conteudo compacto cabe sem rolar na
    // TCL; em telas menores, rola em vez de estourar para fora da
    // area segura. Sem teto (desktop), o corpo direto.
    if (cap == null) return body;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cap),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _mainView(BuildContext context) {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NavRow(
          title: 'Idioma',
          value: _trackLabel(session.audioTracks, session.selectedAudioId) ??
              'Padrão',
          onTap: () => onViewChanged(PlayerPanelView.audio),
        ),
        _NavRow(
          title: 'Legendas',
          value:
              _trackLabel(session.subtitleTracks, session.selectedSubtitleId) ??
                  'Desativadas',
          onTap: () => onViewChanged(PlayerPanelView.subtitles),
        ),
        const Divider(height: 1),
        _NavRow(
          title: 'Repetir',
          value: _repeatLabel(session.repeatMode),
          onTap: () => onViewChanged(PlayerPanelView.repeat),
        ),
        // Qualidade existe com múltiplas faixas de vídeo (spec 13),
        // rendições da fonte (5C) OU variantes HLS reais: sem
        // nenhum dos três, sem linha.
        if (session.videoTracks.length > 1 ||
            _showSourceQualities ||
            _showHlsQualities)
          _NavRow(
            title: 'Qualidade',
            value: _sourceQualityLabel() ??
                _hlsQualityLabel() ??
                _trackLabel(session.videoTracks, session.selectedVideoId) ??
                'Automática',
            onTap: () => onViewChanged(PlayerPanelView.quality),
          ),
        _RotateRow(player: player),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, TvLayout.isTv(context) ? 8.0 : 12.0, 16, 4),
          child: Text('Velocidade de reprodução',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: PlayerTheme.primaryText)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              12, 0, 12, TvLayout.isTv(context) ? 6.0 : 8.0),
          child: Row(
            children: AppConstants.speeds.map((speed) {
              final selected = speed == session.speed;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: TextButton(
                    onPressed: () => player.setSpeed(speed),
                    style: TextButton.styleFrom(
                      backgroundColor: selected
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.transparent,
                      foregroundColor: selected
                          ? PlayerTheme.primaryText
                          : PlayerTheme.secondaryText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                          vertical: TvLayout.isTv(context) ? 5.0 : 10.0),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: Text('${speed}x'.replaceAll('.', ',')),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        _NavRow(
          title: 'Informações do vídeo',
          onTap: () => onViewChanged(PlayerPanelView.info),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, TvLayout.isTv(context) ? 6.0 : 8.0),
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ),
      ],
    );
  }

  Widget _trackSubView(
    BuildContext context, {
    required String title,
    required List<MediaTrack> tracks,
    required String? selectedId,
    required String emptyLabel,
    required Future<void> Function(String?) onSelect,
    String? preferredLanguage,
    bool allowNone = false,
    String noneLabel = '',
  }) {
    // Aviso quando o preferido nao existe (spec 26.12): aparece mesmo
    // com a lista vazia, e nunca tira o usuario do player.
    final want = preferredLanguage?.trim() ?? '';
    final missingPreferred = want.isNotEmpty &&
        findTrackForLanguage(tracks, preferredLanguage) == null;
    return Column(
      key: ValueKey('sub-$title'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: title,
          onBack: () => onViewChanged(PlayerPanelView.main),
        ),
        const Divider(height: 1),
        if (missingPreferred)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Sem faixa em ${languageDisplayName(want)}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        _trackList(
          context,
          tracks: tracks,
          selectedId: selectedId,
          emptyLabel: emptyLabel,
          allowNone: allowNone,
          noneLabel: noneLabel,
          onSelect: onSelect,
        ),
      ],
    );
  }

  /// Lista de faixas (extraida do submenu para reuso na visao de
  /// qualidade com rendicoes: mesma saida, sem cabecalho).
  Widget _trackList(
    BuildContext context, {
    required List<MediaTrack> tracks,
    required String? selectedId,
    required String emptyLabel,
    required Future<void> Function(String?) onSelect,
    bool allowNone = false,
    String noneLabel = '',
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: tracks.isEmpty && !allowNone
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyLabel,
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          : RadioGroup<String?>(
              groupValue: selectedId,
              onChanged: (value) => _choose(() => onSelect(value)),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (allowNone)
                    RadioListTile<String?>(
                      dense: true,
                      title: Text(noneLabel),
                      value: null,
                    ),
                  if (tracks.isEmpty && allowNone)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Text(emptyLabel,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ...tracks.map((track) {
                    final language = _languageOf(track);
                    return RadioListTile<String?>(
                      dense: true,
                      // Rotulo sempre integro: nada de traduzir
                      // titulos (spec 26.12). O idioma vai abaixo.
                      title: Text(track.label),
                      subtitle:
                          language == null ? null : Text(language),
                      value: track.id,
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget _repeatSubView(BuildContext context) {
    return Column(
      key: const ValueKey('sub-repeat'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: 'Repetir',
          onBack: () => onViewChanged(PlayerPanelView.main),
        ),
        const Divider(height: 1),
        RadioGroup<PlaybackRepeatMode>(
          groupValue: session.repeatMode,
          onChanged: (mode) {
            if (mode != null) _choose(() => player.setRepeatMode(mode));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlaybackRepeatMode.values
                .map(
                  (mode) => RadioListTile<PlaybackRepeatMode>(
                    dense: true,
                    title: Text(_repeatLabel(mode)),
                    value: mode,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _infoSubView(BuildContext context) {
    final duration = session.duration;
    return Column(
      key: const ValueKey('sub-info'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: 'Informações do vídeo',
          onBack: () => onViewChanged(PlayerPanelView.main),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(videoTitle ?? 'Vídeo sem título',
                  style: Theme.of(context).textTheme.titleMedium),
              if (duration != null) ...[
                const SizedBox(height: 4),
                Text('Duração: ${duration.timestamp}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (sourceLabel != null) ...[
                const SizedBox(height: 4),
                Text('Fonte: $sourceLabel',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Aplica a escolha e volta a lista principal sem fechar o painel:
  /// a interacao acontece toda dentro do widget.
  Future<void> _choose(Future<void> Function() apply) async {
    await apply();
    onViewChanged(PlayerPanelView.main);
  }

  /// Nome do idioma da faixa para a linha secundaria, ou null quando
  /// o player nao informou codigo.
  static String? _languageOf(MediaTrack track) {
    final code = track.language?.trim() ?? '';
    if (code.isEmpty) return null;
    return languageDisplayName(code);
  }

  static String? _trackLabel(List<MediaTrack> tracks, String? id) {
    if (id == null) return null;
    for (final track in tracks) {
      if (track.id == id) return track.label;
    }
    return null;
  }

  /// Seção da fonte só com rendições (cluster ausente ou vazio:
  /// melhor nem mostrar, como antes).
  bool get _showSourceQualities => source?.qualities.isNotEmpty ?? false;

  bool get _showHlsQualities => (hls?.qualities.length ?? 0) > 1;

  /// Rendicao resolvida (ouvinte ao vivo vale sobre o instantaneo,
  /// como o pai fazia antes de repassar).
  String? get _resolvedSourceId => source?.resolvedId;

  /// Selecao HLS resolvida (ouvinte ao vivo vale sobre o instantaneo).
  String? get _resolvedHlsId => hls?.resolvedId;

  /// Rotulo efetivo resolvido (ouvinte ao vivo vale sobre o instantaneo).
  String? get _resolvedEffectiveLabel => hls?.resolvedEffectiveLabel;

  String? _hlsQualityLabel() {
    if (!_showHlsQualities) return null;
    final hls = this.hls!;
    final id = _resolvedHlsId ?? HlsVariants.autoQualityId;
    if (id == HlsVariants.autoQualityId) {
      // Efetiva visivel: Automatica sozinha nao diz o que abriu.
      final effective = _resolvedEffectiveLabel;
      return effective == null
          ? 'Automática'
          : 'Automática · $effective';
    }
    for (final option in hls.qualities) {
      if (option.id == id) return option.label;
    }
    return 'Automática';
  }

  Widget _hlsList(BuildContext context) {
    final hls = this.hls!;
    final select = hls.onSelect;
    final selected = _resolvedHlsId ?? HlsVariants.autoQualityId;
    // Linhas focaveis (sem RadioGroup): no RadioGroup as setas
    // SELECIONAM ao passar, mas na TV a troca so pode acontecer
    // no OK (Opcoes -> Qualidade -> D-pad -> OK). ListTile move o
    // foco com as setas e so ativa no OK/toque. Coluna sem ListView
    // aninhada: todas montadas; na TV o painel rola por fora.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in hls.qualities)
          ListTile(
            dense: true,
            selected: option.id == selected,
            leading: Icon(
              option.id == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
            ),
            title: Text(option.label),
            subtitle: option.id == HlsVariants.autoQualityId &&
                    _resolvedEffectiveLabel != null
                ? Text('Efetiva: $_resolvedEffectiveLabel')
                : null,
            onTap: () => _choose(() => select(option.id)),
          ),
      ],
    );
  }

  String? _sourceQualityLabel() {
    final source = this.source;
    if (source == null) return null;
    final id = _resolvedSourceId;
    if (id == null) return null;
    for (final quality in source.qualities) {
      if (quality.id == id) return quality.label;
    }
    return null;
  }

  /// Qualidade com rendições da fonte acima das faixas do motor.
  /// Sem rendições, idêntico ao submenu de faixas de antes.
  Widget _qualitySubView(BuildContext context) {
    if (_showHlsQualities && !_showSourceQualities) {
      return Column(
        key: const ValueKey('sub-Qualidade'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SubHeader(
            title: 'Qualidade',
            onBack: () => onViewChanged(PlayerPanelView.main),
          ),
          const Divider(height: 1),
          _hlsList(context),
          if (session.videoTracks.length > 1) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, TvLayout.isTv(context) ? 8.0 : 12.0, 16, 4),
              child: Text('Do vídeo',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            _trackList(
              context,
              tracks: session.videoTracks,
              selectedId: session.selectedVideoId,
              emptyLabel: 'Nenhuma qualidade disponível',
              allowNone: true,
              noneLabel: 'Automática',
              onSelect: player.selectVideo,
            ),
          ],
        ],
      );
    }
    if (!_showSourceQualities) {
      return _trackSubView(
        context,
        title: 'Qualidade',
        tracks: session.videoTracks,
        selectedId: session.selectedVideoId,
        emptyLabel: 'Nenhuma qualidade disponível',
        allowNone: true,
        noneLabel: 'Automática',
        onSelect: player.selectVideo,
      );
    }
    final source = this.source!;
    final select = source.onSelect;
    return Column(
      key: const ValueKey('sub-Qualidade'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: 'Qualidade',
          onBack: () => onViewChanged(PlayerPanelView.main),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, TvLayout.isTv(context) ? 8.0 : 12.0, 16, 4),
          child:
              Text('Da fonte', style: Theme.of(context).textTheme.titleMedium),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: RadioGroup<String?>(
            groupValue: _resolvedSourceId,
            onChanged: (value) => _choose(() => select(value)),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                const RadioListTile<String?>(
                  dense: true,
                  title: Text('Padrão da fonte'),
                  value: null,
                ),
                ...source.qualities.map(
                  (quality) => RadioListTile<String?>(
                    dense: true,
                    title: Text(quality.label),
                    value: quality.id,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, TvLayout.isTv(context) ? 8.0 : 12.0, 16, 4),
          child:
              Text('Do vídeo', style: Theme.of(context).textTheme.titleMedium),
        ),
        _trackList(
          context,
          tracks: session.videoTracks,
          selectedId: session.selectedVideoId,
          emptyLabel: 'Nenhuma qualidade disponível',
          allowNone: true,
          noneLabel: 'Automática',
          onSelect: player.selectVideo,
        ),
        if (_showHlsQualities) ...[
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, TvLayout.isTv(context) ? 8.0 : 12.0, 16, 4),
            child: Text('HLS',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          _hlsList(context),
        ],
      ],
    );
  }

  static String _repeatLabel(PlaybackRepeatMode mode) => switch (mode) {
        PlaybackRepeatMode.off => 'Desativada',
        PlaybackRepeatMode.one => 'Repetir item',
        PlaybackRepeatMode.all => 'Repetir lista',
      };
}

/// Linha de navegacao do painel: titulo, valor atual e seta.
class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, this.value, required this.onTap});

  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(
          horizontal: 16, vertical: TvLayout.isTv(context) ? 1.0 : 2.0),
      hoverColor: Colors.white.withValues(alpha: 0.06),
      // Uma linha sempre: no aparelho cabe folgado e a altura da linha
      // fica estavel (a fonte larga dos testes quebraria em duas).
      // Cor explicita: titulo nunca herda do tema (um tema claro
      // acima apagaria o rotulo no fundo escuro).
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: PlayerTheme.primaryText),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right,
              size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20,
              color: PlayerTheme.secondaryText),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Linha "Girar": dois botoes de quarto de volta que agem na hora,
/// sem sair do painel.
class _RotateRow extends StatelessWidget {
  const _RotateRow({required this.player});

  final MediaPlayerService player;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(
          horizontal: 16, vertical: TvLayout.isTv(context) ? 1.0 : 2.0),
      hoverColor: Colors.white.withValues(alpha: 0.06),
      title: const Text(
        'Girar',
        style: TextStyle(color: PlayerTheme.primaryText),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Girar anti-horário',
            icon: Icon(Icons.rotate_left,
                size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20),
            color: PlayerTheme.secondaryText,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: () => player.rotateCounterClockwise(),
          ),
          IconButton(
            tooltip: 'Girar horário',
            icon: Icon(Icons.rotate_right,
                size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20),
            color: PlayerTheme.secondaryText,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: () => player.rotateClockwise(),
          ),
        ],
      ),
    );
  }
}

/// Seta sob o painel apontando para o botao que o abriu.
class _CaretPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = PlayerSettingsPanel.panelColor,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Cabecalho das sublistas com botao voltar.
class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: Icon(Icons.chevron_left,
              size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20),
          label: const Text('Voltar'),
        ),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: PlayerTheme.primaryText),
          ),
        ),
      ],
    );
  }
}
