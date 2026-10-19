import 'dart:async';

import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/features/addons/addon_display.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/services/addon_service.dart';
import 'package:player/services/thumbnail_service.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/dpad_field_exit.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';

/// Tela de catalogo da fonte (spec 6.1.2): itens validos do feed com
/// busca, paginacao e detalhe rapido com Reproduzir via
/// [resolvePlayback]. So lista com a fonte ativa; falha isolada com
/// tentar de novo; voltar do player retorna ao catalogo (a abertura
/// empilha, nao substitui).
class SourceCatalogScreen extends StatefulWidget {
  const SourceCatalogScreen({
    super.key,
    required this.dependencies,
    required this.addonId,
    this.thumbnailBuilder,
  });

  final AppDependencies dependencies;
  final String addonId;

  /// Constroi o poster remoto; injetavel para testes (evita rede no
  /// `flutter test`, como no [MediaCard]).
  final Widget Function(String url)? thumbnailBuilder;

  @override
  State<SourceCatalogScreen> createState() => _SourceCatalogScreenState();
}

class _SourceCatalogScreenState extends State<SourceCatalogScreen> {
  static const _pageSize = 20;

  final List<AddonCatalogItem> _items = [];
  final TextEditingController _searchController = TextEditingController();
  int _total = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _query;

  AddonInfo? get _info =>
      widget.dependencies.addonService.findById(widget.addonId);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<AddonCatalogPage> _fetchPage(int page) {
    final query = _query;
    if (query != null && query.isNotEmpty) {
      return widget.dependencies.addonService.searchPage(
        widget.addonId,
        query,
        page: page,
        pageSize: _pageSize,
      );
    }
    return widget.dependencies.addonService.getCatalogPage(
      widget.addonId,
      page: page,
      pageSize: _pageSize,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _total = result.totalItems;
        _hasMore = result.hasMore;
      });
    } on AddonError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível carregar o catálogo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final result = await _fetchPage(_items.length ~/ _pageSize + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _total = result.totalItems;
        _hasMore = result.hasMore;
      });
    } on AddonError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível carregar o catálogo.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _search(String query) {
    setState(() => _query = query.trim().isEmpty ? null : query.trim());
    _reload();
  }

  void _clearSearch() {
    _searchController.clear();
    if (_query != null) {
      setState(() => _query = null);
      _reload();
    }
  }

  Future<void> _openSheet(AddonCatalogItem item) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _ItemSheet(
        dependencies: widget.dependencies,
        addonId: widget.addonId,
        item: item,
        thumbnailBuilder: widget.thumbnailBuilder,
      ),
    );
  }

  String _statusLine(AddonInfo info) {
    final updated = info.updatedAt;
    final when = updated == null
        ? 'ainda não atualizado'
        : 'atualizado em ${_date(updated)}';
    return '${addonStateLabel(info.state)} · $when';
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) {
      return AppShell(
        title: 'Catálogo',
        showBack: true,
        body: EmptyState(
          icon: Icons.extension_outlined,
          title: 'Fonte não encontrada',
          message: 'Ela pode ter sido removida.',
          actions: [
            FocusableButton(
              label: 'Voltar',
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
    return AppShell(
      title: info.manifest.name,
      showBack: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusLine(info),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          DpadFieldExit(
            controller: _searchController,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar no catálogo',
                hintText: 'Título ou descrição…',
                border: const OutlineInputBorder(),
                suffixIcon: _query == null
                    ? const Icon(Icons.search)
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
            ),
          ),
          const SizedBox(height: 8),
          if (_query != null)
            Text(
              _total == 1
                  ? '1 resultado para "${_query!}"'
                  : '$_total resultados para "${_query!}"',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
                    ? _CatalogError(
                        message: _error!,
                        onRetry: _reload,
                      )
                    : _items.isEmpty
                        ? const Center(
                            child: Text('Esta fonte não possui itens válidos.'),
                          )
                        : ListView.separated(
                            itemCount: _items.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (index >= _items.length) {
                                return OutlinedButton.icon(
                                  icon: _loadingMore
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.expand_more),
                                  label: const Text('Carregar mais'),
                                  onPressed: _loadingMore ? null : _loadMore,
                                );
                              }
                              final item = _items[index];
                              return _CatalogRow(
                                item: item,
                                autofocus: index == 0,
                                thumbnailBuilder: widget.thumbnailBuilder,
                                onTap: () => _openSheet(item),
                              );
                            },
                          ),
          ),
          if (_error != null && _items.isNotEmpty)
            _CatalogError(message: _error!, onRetry: _loadMore),
        ],
      ),
    );
  }
}

/// Falha isolada da fonte com tentar de novo (nunca trava a tela).
class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}

/// Linha do item: miniatura (ou placeholder), titulo, descricao,
/// duracao e qualidades. Focavel para mouse, teclado e D-pad.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.item,
    required this.autofocus,
    required this.onTap,
    this.thumbnailBuilder,
  });

  final AddonCatalogItem item;
  final bool autofocus;
  final VoidCallback onTap;
  final Widget Function(String url)? thumbnailBuilder;

  @override
  Widget build(BuildContext context) {
    final duration = item.duration;
    final qualities = item.qualities.map((q) => q.label).join(' · ');
    return Card(
      child: InkWell(
        autofocus: autofocus,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 54,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _poster(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (duration != null || qualities.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (duration != null) formatTimestamp(duration),
                          if (qualities.isNotEmpty) qualities,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster(BuildContext context) {
    final url = item.thumbnailUrl;
    if (url == null || url.isEmpty) return _posterFallback();
    if (thumbnailBuilder != null) return thumbnailBuilder!(url);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => _posterFallback(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _posterFallback(),
    );
  }

  static Widget _posterFallback() => const ColoredBox(
        color: Color(0xFF2C2C2E),
        child: Center(child: Icon(Icons.play_arrow)),
      );
}

/// Detalhe rapido do item com acao Reproduzir (spec 6.1.2): resolve
/// pelo adaptador e abre o player pelo fluxo normal, empilhando
/// (voltar retorna ao catalogo). Falha mostra erro controlado e a
/// tela do catalogo segue navegavel.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.dependencies,
    required this.addonId,
    required this.item,
    this.thumbnailBuilder,
  });

  final AppDependencies dependencies;
  final String addonId;
  final AddonCatalogItem item;
  final Widget Function(String url)? thumbnailBuilder;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  bool _opening = false;
  String? _error;

  Future<void> _play() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final media = await widget.dependencies.addonService
          .resolvePlayback(widget.addonId, widget.item);
      final saved = await widget.dependencies.libraryService.upsert(media);
      unawaited(
          ThumbnailService.backfill(widget.dependencies.libraryService, saved));
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.pushNamed(AppRoutes.player, arguments: saved);
    } on AddonError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível abrir esta mídia.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final duration = item.duration;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: widget.thumbnailBuilder != null
                      ? widget.thumbnailBuilder!(item.thumbnailUrl!)
                      : Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => const Center(
                              child: Icon(Icons.play_arrow, size: 40)),
                        ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (duration != null) ...[
              const SizedBox(height: 4),
              Text(
                'Duração: ${formatTimestamp(duration)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (item.qualities.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Qualidades: ${item.qualities.map((q) => q.label).join(', ')}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                autofocus: true,
                icon: _opening
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Reproduzir'),
                onPressed: _opening ? null : _play,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
