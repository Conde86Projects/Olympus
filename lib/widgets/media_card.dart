import 'dart:io';

import 'package:flutter/material.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/app/theme.dart';
import 'package:player/core/extensions/duration_extensions.dart';
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
  static Widget defaultNetworkThumbnailImage(String url) => Image.network(
        url,
        fit: BoxFit.cover,
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

  String _detailsLine() {
    final parts = <String>[];
    if (item.duration != null) parts.add(item.duration!.timestamp);
    if (item.lastPosition != null && item.isResumable) {
      parts.add('parou em ${item.lastPosition!.timestamp}');
    }
    parts.add(item.sourceType == MediaSourceType.local ? 'Arquivo' : 'Link');
    return parts.join(' · ');
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item, this.builder, this.networkBuilder});

  final MediaItem item;
  final Widget Function(String path)? builder;
  final Widget Function(String url)? networkBuilder;

  @override
  Widget build(BuildContext context) {
    // Ordem: miniatura local, pôster da fonte, placeholder.
    final thumb = item.thumbnailPath;
    final poster = item.metadata['posterUrl'];
    Widget? image;
    if (thumb != null) {
      image = builder?.call(thumb) ?? MediaCard.defaultThumbnailImage(thumb);
    } else if (poster != null && poster.isNotEmpty) {
      image = networkBuilder?.call(poster) ??
          MediaCard.defaultNetworkThumbnailImage(poster);
    }
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
  });

  final MediaItem item;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRemove;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    if (onToggleFavorite == null && onRemove == null && onRestart == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
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
