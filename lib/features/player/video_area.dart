import 'package:flutter/material.dart';

import 'package:player/app/theme.dart';
import 'package:player/app/tv_layout.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/models/playback_state.dart';
import 'package:player/services/media_player_service.dart';
import 'package:player/widgets/empty_state.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/player_settings_panel.dart';

/// Area do video com estados (carregando, erro, concluido, oferta "Ver de
/// novo", proxima) e cancelar. Extraida de player_screen.dart sem mudanca
/// de comportamento.

class VideoArea extends StatelessWidget {
  const VideoArea({
    super.key,
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
    return _FocusOnMount(
      focusNode: primaryFocus,
      child: Center(
        child: Container(
          padding: isTv
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
              : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: PlayerSettingsPanel.panelColor,
            borderRadius:
                BorderRadius.circular(isTv ? tokens!.panelRadius : 12),
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

/// Pede o foco ao montar (uma vez): o cartão de "Ver de novo" aparece
/// depois da transição de abertura, então o foco precisa ser transferido
/// quando ele existe de fato.
class _FocusOnMount extends StatefulWidget {
  const _FocusOnMount({required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  State<_FocusOnMount> createState() => _FocusOnMountState();
}

class _FocusOnMountState extends State<_FocusOnMount> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
