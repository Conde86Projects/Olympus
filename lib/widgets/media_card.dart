import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/core/utils/last_seen.dart';
import 'package:player/models/media_item.dart';

/// Cartao de midia para biblioteca, favoritos e "Continuar assistindo".
/// Mostra miniatura (ou placeholder), titulo, duracao, progresso e favorito.
/// Focavel por teclado/controle remoto (spec 18).
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    this.onTap,
    this.onToggleFavorite,
    this.onRemove,
    this.onRestart,
    this.autofocus = false,
    this.thumbnailBuilder,
    this.networkThumbnailBuilder,
    this.now,
  });

  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRemove;
  final VoidCallback? onRestart;
  final bool autofocus;

  /// Constrói a miniatura a partir do caminho. O padrão é
  /// [defaultThumbnailImage]; injetável para testes (o decode real de
  /// `Image.file` trava o `flutter test` neste ambiente Windows).
  final Widget Function(String path)? thumbnailBuilder;

  /// Constrói o pôster remoto (`metadata['posterUrl']`) quando não há
  /// miniatura local. O padrão é [defaultNetworkThumbnailImage];
  /// injetável para testes (evita rede no `flutter test`).
  final Widget Function(String url)? networkThumbnailBuilder;

  /// Relógio injetável (testes) para o texto do último acesso.
  final DateTime? now;

  /// Miniatura padrão: arquivo com fallback para o placeholder.
  /// Chamado sem pump nos testes (só inspeciona o widget).
  @visibleForTesting
  static Widget defaultThumbnailImage(String path) => Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Icon(Icons.play_arrow,
            color: PlayerTheme.secondaryText,
            size: TvLayout.isTv(context)
                ? TvLayout.tokensOf(context).iconPrimary
                : 28),
      );

  /// Pôster remoto padrão: carrega com o placeholder visível e cai
  /// nele em qualquer erro. Chamado sem pump nos testes.
  @visibleForTesting
  static Widget defaultNetworkThumbnailImage(String url,
          {BoxFit fit = BoxFit.cover}) =>
      Image.network(
        url,
        // Pôster de 4000 px decodificado inteiro pesa na memória da TV. Com
        // 960, o maior cartão ainda fica nítido na tela 2x.
        cacheWidth: 960,
        fit: fit,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Icon(Icons.play_arrow,
                color: PlayerTheme.secondaryText,
                size: TvLayout.isTv(context)
                    ? TvLayout.tokensOf(context).iconPrimary
                    : 28),
        errorBuilder: (context, error, stack) => Icon(Icons.play_arrow,
            color: PlayerTheme.secondaryText,
            size: TvLayout.isTv(context)
                ? TvLayout.tokensOf(context).iconPrimary
                : 28),
      );

  @override
  Widget build(BuildContext context) {
    final progress = item.progress;
    // Destaque do cartao inteiro, como em Add-ons: o foco de qualquer
    // parte (corpo ou menu) pinta o cartao todo, com os cantos
    // arredondados. Antes o foco ficava so no corpo: faixa cortada.
    return _FocusCard(
      builder: (focused) => Card(
        color: focused
            ? Color.alphaBlend(
                PlayerTheme.accent.withValues(alpha: 0.25), _cardColor)
            : _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(TvLayout.spacing(context, 12)),
          child: Row(
            children: [
              Expanded(
                // Corpo focavel separado do menu (F7, Fase 4b): com o
                // Opcoes dentro do InkWell, o RIGHT partia do cartao
                // inteiro e pulava o botao para a barra superior.
                child: InkWell(
                  autofocus: autofocus,
                  onTap: onTap,
                  // O destaque e do cartao todo (_FocusCard); sem o foco
                  // retangular do proprio corpo.
                  focusColor: Colors.transparent,
                  child: Row(
                    children: [
                      _Thumbnail(
                        item: item,
                        builder: thumbnailBuilder,
                        networkBuilder: networkThumbnailBuilder,
                      ),
                      SizedBox(width: TvLayout.spacing(context, 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: TvLayout.spacing(context, 4)),
                            Text(
                              _detailsLine(),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (lastSeenLabel(
                                    item.lastPlayedAt, now ?? DateTime.now())
                                case final seen?) ...[
                              SizedBox(height: TvLayout.spacing(context, 2)),
                              Text(
                                seen,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            if (progress != null && progress > 0) ...[
                              SizedBox(height: TvLayout.spacing(context, 8)),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: TvLayout.isTv(context) ? 6 : 4,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.12),
                                  valueColor: const AlwaysStoppedAnimation(
                                      PlayerTheme.accent),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (item.isFavorite)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.favorite,
                              size: TvLayout.isTv(context)
                                  ? TvLayout.tokensOf(context).iconSecondary
                                  : 18,
                              color: PlayerTheme.accent),
                        ),
                    ],
                  ),
                ),
              ),
              _OverflowMenu(
                item: item,
                onToggleFavorite: onToggleFavorite,
                onRemove: onRemove,
                onRestart: onRestart,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailsLine() => _mediaDetailsLine(item);
}

String _mediaDetailsLine(MediaItem item) {
  final parts = <String>[];
  if (item.duration != null) parts.add(item.duration!.timestamp);
  if (item.lastPosition != null && item.isResumable) {
    parts.add('parou em ${item.lastPosition!.timestamp}');
  }
  parts.add(item.sourceType == MediaSourceType.local ? 'Arquivo' : 'Link');
  return parts.join(' · ');
}

/// Cartão vertical das fileiras do Início: imagem grande com o título
/// embaixo. A proporção vem de quem chama: quadro de vídeo em
/// [frameAspect] e pôster de catálogo em [posterAspect]. O menu não
/// entra na navegação por setas (a fileira anda de cartão em cartão);
/// abre pelo botão, pelo clique direito e pela tecla de menu.
class MediaPosterCard extends StatefulWidget {
  const MediaPosterCard({
    super.key,
    required this.item,
    required this.width,
    this.aspectRatio = frameAspect,
    this.onTap,
    this.onToggleFavorite,
    this.onRemove,
    this.onRestart,
    this.autofocus = false,
    this.thumbnailBuilder,
    this.networkThumbnailBuilder,
    this.detail,
  });

  /// Linha abaixo do título; nula usa duração, posição e origem.
  final String? detail;

  static const frameAspect = 16 / 9;
  static const posterAspect = 2 / 3;

  final MediaItem item;
  final double width;
  final double aspectRatio;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRemove;
  final VoidCallback? onRestart;
  final bool autofocus;
  final Widget Function(String path)? thumbnailBuilder;
  final Widget Function(String url)? networkThumbnailBuilder;

  /// Altura total: imagem + legenda (respeita o tamanho do texto).
  static double heightFor(
    BuildContext context, {
    required double width,
    required double aspectRatio,
  }) {
    final caption = MediaQuery.textScalerOf(context).scale(_captionHeight);
    return width / aspectRatio +
        _captionGap +
        (caption < _captionMin ? _captionMin : caption);
  }

  static const _captionGap = 8.0;
  static const _captionHeight = 52.0;
  static const _captionMin = 48.0;

  @override
  State<MediaPosterCard> createState() => _MediaPosterCardState();
}

class _MediaPosterCardState extends State<MediaPosterCard> {
  final _menu = GlobalKey<PopupMenuButtonState<String>>();
  bool _focused = false;
  bool _hovered = false;

  bool get _hasMenu =>
      widget.onToggleFavorite != null ||
      widget.onRemove != null ||
      widget.onRestart != null;

  void _openMenu() => _menu.currentState?.showButtonMenu();

  /// O foco mora na imagem, e a lista só rola até ela: na última fileira
  /// visível o título ficava para fora. Janela menor que o cartão fica
  /// como está, senão a imagem focada é que sairia.
  void _revealCaption() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = context.size?.height ?? 0;
      if (height >= MediaQuery.sizeOf(context).height * 0.7) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final progress = item.progress;
    final image = _mediaImage(
      item,
      widget.thumbnailBuilder,
      widget.networkThumbnailBuilder,
      portraitCard: widget.aspectRatio < 1,
    );
    final borderColor = _focused
        ? PlayerTheme.accent
        : _hovered
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.08);
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (value) {
                setState(() => _focused = value);
                if (value) _revealCaption();
              },
              onKeyEvent: (node, event) {
                if (_hasMenu &&
                    event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.contextMenu) {
                  _openMenu();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onSecondaryTap: _hasMenu ? _openMenu : null,
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: Material(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      autofocus: widget.autofocus,
                      onTap: widget.onTap,
                      focusColor: Colors.transparent,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          image ??
                              const Center(
                                child: Icon(Icons.play_arrow,
                                    size: 40,
                                    color: PlayerTheme.secondaryText),
                              ),
                          if (item.isFavorite)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.favorite,
                                    size: 16, color: PlayerTheme.accent),
                              ),
                            ),
                          if (progress != null && progress > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.45),
                                valueColor: const AlwaysStoppedAnimation(
                                    PlayerTheme.accent),
                              ),
                            ),
                          // Borda por cima da imagem, sempre visível.
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: borderColor,
                                  width: _focused
                                      ? (TvLayout.isTv(context)
                                          ? TvLayout.tokensOf(context)
                                              .focusRingWidth
                                          : 3)
                                      : 1,
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
          const SizedBox(height: MediaPosterCard._captionGap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          widget.detail ?? _mediaDetailsLine(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_hasMenu)
                  // Controle remoto não tem clique direito nem tecla de
                  // menu garantida: na TV o botão entra na navegação
                  // (seta para baixo a partir da imagem).
                  ExcludeFocus(
                    excluding: !TvLayout.isTv(context),
                    child: _OverflowMenu(
                      menuKey: _menu,
                      item: item,
                      onToggleFavorite: widget.onToggleFavorite,
                      onRemove: widget.onRemove,
                      onRestart: widget.onRestart,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Imagem do item: miniatura local, pôster da fonte ou nada.
Widget? _mediaImage(
  MediaItem item,
  Widget Function(String path)? builder,
  Widget Function(String url)? networkBuilder, {
  bool portraitCard = false,
}) {
  final thumb = item.thumbnailPath;
  final poster = item.metadata['posterUrl'];
  if (thumb != null) {
    return builder?.call(thumb) ?? MediaCard.defaultThumbnailImage(thumb);
  }
  if (poster != null && poster.isNotEmpty) {
    if (networkBuilder != null) return networkBuilder(poster);
    return portraitCard
        ? PosterFitByShape(url: poster)
        : MediaCard.defaultNetworkThumbnailImage(poster);
  }
  return null;
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item, this.builder, this.networkBuilder});

  final MediaItem item;
  final Widget Function(String path)? builder;
  final Widget Function(String url)? networkBuilder;

  @override
  Widget build(BuildContext context) {
    // Ordem: miniatura local, pôster da fonte, placeholder.
    final image = _mediaImage(item, builder, networkBuilder);
    return Container(
      width:
          TvLayout.isTv(context) ? TvLayout.tokensOf(context).thumbWidth : 96,
      height:
          TvLayout.isTv(context) ? TvLayout.tokensOf(context).thumbHeight : 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: image ??
          Icon(Icons.play_arrow,
              color: PlayerTheme.secondaryText,
              size: TvLayout.isTv(context)
                  ? TvLayout.tokensOf(context).iconPrimary
                  : 28),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.item,
    this.onToggleFavorite,
    this.onRemove,
    this.onRestart,
    this.menuKey,
  });

  final MediaItem item;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRemove;
  final VoidCallback? onRestart;
  final GlobalKey<PopupMenuButtonState<String>>? menuKey;

  @override
  Widget build(BuildContext context) {
    if (onToggleFavorite == null && onRemove == null && onRestart == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      key: menuKey,
      tooltip: 'Opções',
      icon: const Icon(Icons.more_vert, color: PlayerTheme.secondaryText),
      onSelected: (value) {
        switch (value) {
          case 'favorite':
            onToggleFavorite?.call();
          case 'restart':
            onRestart?.call();
          case 'remove':
            onRemove?.call();
        }
      },
      itemBuilder: (_) => [
        if (onRestart != null && item.isResumable)
          const PopupMenuItem(
              value: 'restart', child: _MenuItemLabel('Recomeçar do zero')),
        if (onToggleFavorite != null)
          PopupMenuItem(
            value: 'favorite',
            child: _MenuItemLabel(item.isFavorite
                ? 'Remover dos favoritos'
                : 'Adicionar aos favoritos'),
          ),
        if (onRemove != null)
          const PopupMenuItem(
              value: 'remove',
              child: _MenuItemLabel('Remover', destructive: true)),
      ],
    );
  }
}

const _cardColor = Color(0xFF1C1C1E);

/// Detecta foco em qualquer descendente (corpo ou menu) e repassa ao
/// [builder]. O proprio nó nao recebe foco nem entra na navegacao.
class _FocusCard extends StatefulWidget {
  const _FocusCard({required this.builder});

  final Widget Function(bool focused) builder;

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) {
          if (value != _focused) setState(() => _focused = value);
        },
        child: widget.builder(_focused),
      );
}

/// Rótulo de item do menu com foco visível (controle remoto e teclado): a
/// borda e o fundo acompanham o foco, como nos botões do app. Sem isso, o
/// destaque padrão do menu some na TV. A ação destrutiva fica vermelha.
class _MenuItemLabel extends StatelessWidget {
  const _MenuItemLabel(this.label, {this.destructive = false});

  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    // O foco do item é o do InkWell do PopupMenuItem, o Focus mais próximo.
    final node = Focus.of(context);
    final color = destructive ? PlayerTheme.error : PlayerTheme.accent;
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final focused = node.hasFocus;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: focused ? color.withValues(alpha: 0.22) : null,
            borderRadius: BorderRadius.circular(8),
            border: focused ? Border.all(color: color, width: 2) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: focused ? Colors.white : PlayerTheme.primaryText,
              fontWeight: focused ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      },
    );
  }
}

/// Pôster remoto no cartão em pé (2:3): imagem horizontal aparece inteira,
/// com o fundo do cartão nas sobras, em vez de ter as pontas cortadas. A
/// forma vem do decode, que o cache de imagens compartilha com o desenho.
/// [providerFor] troca a imagem nos testes.
@visibleForTesting
class PosterFitByShape extends StatefulWidget {
  const PosterFitByShape({super.key, required this.url, this.providerFor});

  final String url;
  final ImageProvider Function(String url)? providerFor;

  @override
  State<PosterFitByShape> createState() => _PosterFitByShapeState();
}

class _PosterFitByShapeState extends State<PosterFitByShape> {
  BoxFit _fit = BoxFit.cover;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      final fit = posterFitFor(info.image.width, info.image.height);
      if (mounted && fit != _fit) setState(() => _fit = fit);
    },
    onError: (_, __) {},
  );

  ImageProvider get _provider =>
      widget.providerFor?.call(widget.url) ??
      ResizeImage(NetworkImage(widget.url), width: 960);

  void _subscribe() {
    _stream = _provider.resolve(const ImageConfiguration())
      ..addListener(_listener);
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(PosterFitByShape old) {
    super.didUpdateWidget(old);
    // Cartão reaproveitado com outro pôster: encaixe e inscrição recomeçam.
    if (old.url != widget.url) {
      _stream?.removeListener(_listener);
      _fit = BoxFit.cover;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.providerFor == null
      ? MediaCard.defaultNetworkThumbnailImage(widget.url, fit: _fit)
      : Image(image: _provider, fit: _fit);
}

/// Encaixe do pôster no cartão em pé: horizontal inteiro, vertical cobrindo.
@visibleForTesting
BoxFit posterFitFor(int width, int height) =>
    width > height ? BoxFit.contain : BoxFit.cover;
