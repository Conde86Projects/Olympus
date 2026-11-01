import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/routes.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/extensions/duration_extensions.dart';
import 'package:player/features/addons/catalog_playback.dart';
import 'package:player/features/home/home_addon_rows.dart';
import 'package:player/features/home/home_sections.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/media_item.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/startup_guard.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/app_toast.dart';
import 'package:player/widgets/confirm_dialog.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/media_card.dart';

/// Tela inicial (spec 8): "Continuar assistindo", abrir arquivo/link e acesso
/// a biblioteca, favoritos, historico e configuracoes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    // O menu acompanha a escolha de destinos em Configuracoes.
    return AnimatedBuilder(
      animation: dependencies.preferencesService,
      builder: (context, _) => _buildScreen(
          context, dependencies.preferencesService.current.hiddenDestinations),
    );
  }

  Widget _buildScreen(BuildContext context, List<MainDestination> hidden) {
    bool shown(MainDestination d) => !hidden.contains(d);
    final guard = dependencies.startupGuard;
    // No celular, Biblioteca, Add-ons, Favoritos e Configuracoes moram
    // na navegacao inferior ([MobileShell]); o Historico fica aqui.
    final mobile = MobileMode.of(context);
    // T7: no desktop o Início mostra fileiras e ocupa a janela toda;
    // celular e TV seguem na lista vertical de antes.
    final desktop = !mobile && !TvLayout.isTv(context);
    return AppShell(
      title: 'Olympus',
      showLogo: true,
      maxWidth: desktop ? null : 1080,
      actions: [
        if (!mobile && shown(MainDestination.library))
        IconButton(
          tooltip: 'Biblioteca',
          icon: const Icon(Icons.video_library_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.library),
        ),
        if (!mobile && shown(MainDestination.addons))
        IconButton(
          tooltip: 'Add-ons',
          icon: const Icon(Icons.extension_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.addons),
        ),
        if (!mobile && shown(MainDestination.favorites))
        IconButton(
          tooltip: 'Favoritos',
          icon: const Icon(Icons.favorite_outline),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.favorites),
        ),
        if (shown(MainDestination.history))
        IconButton(
          tooltip: 'Histórico',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.history),
        ),
        if (!mobile)
        IconButton(
          tooltip: 'Configurações',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
        ),
      ],
      body: desktop
          ? _DesktopHome(home: this)
          : _classicBody(context, guard),
    );
  }

  /// Lista vertical de antes (celular e TV, T7): "Continuar
  /// assistindo" com a regra movida para [continueWatchingItems].
  Widget _classicBody(BuildContext context, StartupGuard guard) {
    final library = dependencies.libraryService;
    final history = dependencies.historyService;
    return Column(
      children: [
        AnimatedBuilder(
          animation: guard,
          builder: (context, _) => guard.safeMode
              ? _SafeModeBanner(guard: guard)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([library, history]),
            builder: (context, _) {
              final resume = continueWatchingItems(
                entries: history.entries,
                byId: itemsById(library.items),
              );
              if (resume.isEmpty) return _empty(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Continuar assistindo',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: resume.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = resume[index];
                        return MediaCard(
                          item: item,
                          autofocus: index == 0,
                          onTap: () => _play(context, item),
                          onRestart: () =>
                              _play(context, item, fromStart: true),
                          onToggleFavorite: () =>
                              library.toggleFavorite(item.id),
                          onRemove: () =>
                              _removeFromHistory(context, item),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _openActions(context),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Largura do cartão da fileira: acompanha a janela só até 360; daí
  /// em diante, mais janela mostra mais cartões, não cartões maiores.
  static double rowCardWidth(double windowWidth) =>
      (windowWidth / 6).clamp(240.0, 360.0);

  /// Largura do pôster de catálogo, no mesmo critério do cartão.
  static double rowPosterWidth(double windowWidth) =>
      (windowWidth / 8).clamp(160.0, 240.0);

  /// F3 (Fase 4b): confirma antes de tirar do histórico; o item
  /// continua na biblioteca.
  Future<void> _removeFromHistory(BuildContext context, MediaItem item) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Remover do histórico?',
      message:
          "'${item.title}' sai do histórico. O item continua na biblioteca.",
    );
    if (confirmed) dependencies.historyService.remove(item.id);
  }

  Widget _empty(BuildContext context, {bool withAddons = false}) {
    return EmptyState(
      icon: Icons.play_circle_outline,
      title: 'Nenhum vídeo por aqui ainda',
      message:
          'Ainda não há vídeos aqui. Abra um arquivo ou um link para começar.',
      actions: [
        FocusableButton(
          label: 'Abrir arquivo',
          icon: Icons.folder_open,
          primary: true,
          autofocus: true,
          onPressed: () => _openMedia(context, OpenMediaTab.file),
        ),
        FocusableButton(
          label: 'Abrir link',
          icon: Icons.link,
          onPressed: () => _openMedia(context, OpenMediaTab.link),
        ),
        if (withAddons)
          FocusableButton(
            label: 'Instalar add-on',
            icon: Icons.extension_outlined,
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.addons),
          ),
      ],
    );
  }

  Widget _openActions(BuildContext context) {
    return Wrap(
      spacing: 12,
      children: [
        FocusableButton(
          label: 'Abrir arquivo',
          icon: Icons.folder_open,
          onPressed: () => _openMedia(context, OpenMediaTab.file),
        ),
        FocusableButton(
          label: 'Abrir link',
          icon: Icons.link,
          onPressed: () => _openMedia(context, OpenMediaTab.link),
        ),
      ],
    );
  }

  void _play(BuildContext context, MediaItem item, {bool fromStart = false}) {
    final target = fromStart ? item.copyWith(lastPosition: () => null) : item;
    Navigator.of(context).pushNamed(AppRoutes.player, arguments: target);
  }

  void _openMedia(BuildContext context, OpenMediaTab tab) {
    Navigator.of(context).pushNamed(
      AppRoutes.openMedia,
      arguments: OpenMediaArgs(tab: tab),
    );
  }
}

/// Início do desktop: fileiras locais (T7) e uma por add-on ativo (T8).
/// Os catálogos ficam em memória aqui: voltar do player não busca de novo.
class _DesktopHome extends StatefulWidget {
  const _DesktopHome({required this.home});

  final HomeScreen home;

  @override
  State<_DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<_DesktopHome> {
  late final HomeAddonRows _rows;

  AppDependencies get _deps => widget.home.dependencies;

  @override
  void initState() {
    super.initState();
    _rows = HomeAddonRows(
      _deps.addonService,
      hidden: () => _deps.preferencesService.current.hiddenDestinations,
      safeMode: () => _deps.startupGuard.safeMode,
    );
    _deps.preferencesService.addListener(_rows.reconcile);
    _deps.startupGuard.addListener(_rows.reconcile);
    // Depois da primeira pintura: a tela nunca espera a rede.
    WidgetsBinding.instance.addPostFrameCallback((_) => _rows.reconcile());
  }

  @override
  void dispose() {
    _deps.preferencesService.removeListener(_rows.reconcile);
    _deps.startupGuard.removeListener(_rows.reconcile);
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = _deps.libraryService;
    final history = _deps.historyService;
    final guard = _deps.startupGuard;
    final hidden = _deps.preferencesService.current.hiddenDestinations;
    return Column(
      children: [
        AnimatedBuilder(
          animation: guard,
          builder: (context, _) => guard.safeMode
              ? _SafeModeBanner(guard: guard)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([library, history, _rows]),
            builder: (context, _) {
              final sections = homeSections(
                entries: history.entries,
                items: library.items,
                hidden: hidden,
              );
              final addons = _rows.visibleInfos;
              if (sections.isEmpty && addons.isEmpty) {
                return widget.home._empty(
                  context,
                  withAddons: !hidden.contains(MainDestination.addons),
                );
              }
              return ListView.separated(
                itemCount: 1 + sections.length + addons.length,
                separatorBuilder: (_, __) => const SizedBox(height: 24),
                itemBuilder: (context, index) {
                  if (index == 0) return widget.home._openActions(context);
                  final at = index - 1;
                  if (at < sections.length) {
                    return _localRow(
                      context,
                      sections[at],
                      autofocusFirst: at == 0,
                    );
                  }
                  final position = at - sections.length;
                  final info = addons[position];
                  return _AddonRow(
                    key: ValueKey('home-addon-${info.manifest.id}'),
                    dependencies: _deps,
                    info: info,
                    state: _rows.stateOf(info.manifest.id),
                    autofocusFirst: sections.isEmpty && position == 0,
                    onRefresh: () => _rows.refresh(info.manifest.id),
                    onRetry: () => _rows.retry(info.manifest.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _localRow(
    BuildContext context,
    HomeSection section, {
    required bool autofocusFirst,
  }) {
    final library = _deps.libraryService;
    final home = widget.home;
    final width = HomeScreen.rowCardWidth(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(section.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: MediaPosterCard.heightFor(
            context,
            width: width,
            aspectRatio: MediaPosterCard.frameAspect,
          ),
          child: ListView.separated(
            key: PageStorageKey<String>('home-row-${section.kind.name}'),
            scrollDirection: Axis.horizontal,
            itemCount: section.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final item = section.items[i];
              return MediaPosterCard(
                key: ValueKey(item.id),
                item: item,
                width: width,
                autofocus: autofocusFirst &&
                    i == 0 &&
                    ModalRoute.of(context)?.isCurrent == true,
                onTap: () => home._play(context, item),
                onRestart: () => home._play(context, item, fromStart: true),
                onToggleFavorite: () => library.toggleFavorite(item.id),
                onRemove: section.kind == HomeSectionKind.resume
                    ? () => home._removeFromHistory(context, item)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Fileira de um add-on (T8): nome, "Ver tudo", "Atualizar" e pôsteres.
/// Carga e falha ficam só nela.
class _AddonRow extends StatefulWidget {
  const _AddonRow({
    super.key,
    required this.dependencies,
    required this.info,
    required this.state,
    required this.autofocusFirst,
    required this.onRefresh,
    required this.onRetry,
  });

  final AppDependencies dependencies;
  final AddonInfo info;
  final HomeAddonRowState state;
  final bool autofocusFirst;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;

  @override
  State<_AddonRow> createState() => _AddonRowState();
}

class _AddonRowState extends State<_AddonRow> {
  bool _opening = false;

  String get _addonId => widget.info.manifest.id;

  Future<void> _play(AddonCatalogItem item) async {
    if (_opening) return;
    _opening = true;
    try {
      final saved = await prepareCatalogItem(
        widget.dependencies,
        _addonId,
        item,
      );
      if (!mounted) return;
      await Navigator.of(context).pushNamed(AppRoutes.player, arguments: saved);
    } on AddonError catch (error) {
      if (mounted) showAppToast(context, error.message, error: true);
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Não foi possível abrir esta mídia.',
            error: true);
      }
    } finally {
      _opening = false;
    }
  }

  /// Item do catálogo no formato do cartão, só para desenhar: quem vai
  /// para a biblioteca é o que o add-on resolve ao abrir.
  MediaItem _preview(AddonCatalogItem item) => MediaItem(
        id: '$_addonId:${item.id}',
        title: item.title,
        subtitle: item.subtitle,
        sourceType: MediaSourceType.url,
        source: item.sourceUrl,
        duration: item.duration,
        addedAt: DateTime.fromMillisecondsSinceEpoch(0),
        metadata: {
          if (item.thumbnailUrl != null) 'posterUrl': item.thumbnailUrl!,
        },
      );

  String _detailOf(AddonCatalogItem item) {
    final subtitle = item.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) return subtitle;
    final duration = item.duration;
    return duration == null ? 'Catálogo' : duration.timestamp;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final width = HomeScreen.rowPosterWidth(MediaQuery.sizeOf(context).width);
    final height = MediaPosterCard.heightFor(
      context,
      width: width,
      aspectRatio: MediaPosterCard.posterAspect,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.info.manifest.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
            ),
            FocusableButton(
              label: 'Ver tudo',
              onPressed: () => Navigator.of(context).pushNamed(
                AppRoutes.sourceCatalog,
                arguments: _addonId,
              ),
            ),
            const SizedBox(width: 8),
            // Sempre habilitado: desabilitar tiraria o foco do teclado no
            // meio da carga. Clicar de novo enquanto carrega não repete.
            FocusableButton(
              label: 'Atualizar',
              icon: Icons.refresh,
              onPressed: widget.onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.error != null)
          Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Flexible(
                child: Text(state.error!, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 12),
              FocusableButton(
                label: 'Tentar de novo',
                icon: Icons.refresh,
                onPressed: widget.onRetry,
              ),
            ],
          )
        else if (state.items.isEmpty)
          // Reserva a altura da fileira: chegar o catálogo não pula a tela.
          SizedBox(
            height: height,
            child: const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
          )
        else
          SizedBox(
            height: height,
            child: ListView.separated(
              key: PageStorageKey<String>('home-addon-row-$_addonId'),
              scrollDirection: Axis.horizontal,
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final item = state.items[i];
                return MediaPosterCard(
                  key: ValueKey(item.id),
                  item: _preview(item),
                  width: width,
                  aspectRatio: MediaPosterCard.posterAspect,
                  detail: _detailOf(item),
                  autofocus: widget.autofocusFirst &&
                      i == 0 &&
                      ModalRoute.of(context)?.isCurrent == true,
                  onTap: () => _play(item),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Faixa de modo seguro (spec 6.1): informa o motivo, oferece desativar
/// a ultima alteracao de add-on e some so com o reinicio.
class _SafeModeBanner extends StatefulWidget {
  const _SafeModeBanner({required this.guard});

  final StartupGuard guard;

  @override
  State<_SafeModeBanner> createState() => _SafeModeBannerState();
}

class _SafeModeBannerState extends State<_SafeModeBanner> {
  late Future<LastAddonChange?> _change;

  @override
  void initState() {
    super.initState();
    _change = widget.guard.readLastChange();
    widget.guard.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.guard.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _change = widget.guard.readLastChange();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guard = widget.guard;
    final reason = guard.safeModeReason == SafeModeReason.manual
        ? 'Modo seguro ativado manualmente: add-ons não carregados.'
        : 'Modo seguro: add-ons não carregados '
            '(${guard.consecutiveFailures} falhas no arranque).';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber,
                  size: TvLayout.isTv(context) ? TvLayout.tokensOf(context).iconSecondary : 20,
                  color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(reason, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FutureBuilder<LastAddonChange?>(
                  future: _change,
                  builder: (context, snapshot) {
                    final change = snapshot.data;
                    if (change == null) {
                      return const SizedBox.shrink();
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Última alteração: ${change.name}.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FocusableButton(
                          label: 'Desativar última alteração',
                          icon: Icons.toggle_off,
                          onPressed: () => _disable(context),
                        ),
                      ],
                    );
                  },
                ),
                FocusableButton(
                  label: 'Diagnóstico',
                  icon: Icons.health_and_safety,
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.diagnostics,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disable(BuildContext context) async {
    final disabled = await widget.guard.disableLastChange();
    if (!context.mounted) return;
    showAppToast(
      context,
      disabled
          ? 'Última alteração desativada. Reinicie para sair do modo seguro.'
          : 'Nada a desativar.',
    );
  }
}
