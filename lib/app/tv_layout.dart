import 'package:flutter/widgets.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/tv_mode.dart';

/// Classe de largura logica (spec 27.4). A decisao de layout usa a
/// largura logica + o contexto de TV (Leanback ou manual), nunca so a
/// diagonal fisica: uma TV 720p, uma 1080p e uma 4K informam larguras
/// logicas diferentes e cada uma recebe seus tokens.
enum TvWidthClass {
  /// Largura logica abaixo de 800 (ex.: TV 720p em 320 dpi = 640).
  compact,

  /// 800 ate 1279 (ex.: TV 1080p em 320 dpi = 960).
  normal,

  /// 1280 ou mais (ex.: TV 4K em 320 dpi = 1920).
  big,
}

/// Tokens de layout da TV (spec 27.7). Separados dos numeros do
/// desktop de proposito: icones principais crescem, secundarios nao
/// acompanham na mesma proporcao, e cada classe de largura tem seu
/// conjunto. Fora do modo TV, ninguem consulta estes tokens.
class TvLayoutTokens {
  const TvLayoutTokens({
    required this.iconPrimary,
    required this.iconSecondary,
    required this.textTitle,
    required this.textBody,
    required this.textCaption,
    required this.controlHeight,
    required this.focusRingWidth,
    required this.panelRadius,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.volumeTrackWidth,
    required this.minTextScale,
    required this.maxTextScale,
  });

  /// Icone de destaque (placeholder de cartao, cabecalhos).
  final double iconPrimary;

  /// Icone de linha/acao (proporcao menor que o primario).
  final double iconSecondary;

  /// Titulo de cartao/barra.
  final double textTitle;

  /// Texto de linha.
  final double textBody;

  /// Texto auxiliar.
  final double textCaption;

  /// Altura minima de controle focavel.
  final double controlHeight;

  /// Espessura do anel de foco.
  final double focusRingWidth;

  /// Raio do painel/barra da TV.
  final double panelRadius;

  /// Miniatura do cartao de midia.
  final double thumbWidth;
  final double thumbHeight;

  /// Trilho de volume da barra da TV.
  final double volumeTrackWidth;

  /// Faixa do escalonador de texto nesta classe. Minimo 1.0 em todas:
  /// a TV nao forca ampliacao (verificado na TCL 50"); a escala do
  /// sistema segue respeitada ate o maximo (acessibilidade).
  final double minTextScale;
  final double maxTextScale;

  static const compact = TvLayoutTokens(
    iconPrimary: 20,
    iconSecondary: 16,
    textTitle: 20,
    textBody: 15,
    textCaption: 12,
    controlHeight: 44,
    focusRingWidth: 3,
    panelRadius: 14,
    thumbWidth: 96,
    thumbHeight: 56,
    volumeTrackWidth: 96,
    minTextScale: 1.0,
    maxTextScale: 1.2,
  );

  static const normal = TvLayoutTokens(
    iconPrimary: 24,
    iconSecondary: 18,
    textTitle: 22,
    textBody: 17,
    textCaption: 12,
    controlHeight: 44,
    focusRingWidth: 3,
    panelRadius: 16,
    thumbWidth: 96,
    thumbHeight: 56,
    volumeTrackWidth: 128,
    minTextScale: 1.0,
    maxTextScale: 1.3,
  );

  static const big = TvLayoutTokens(
    iconPrimary: 28,
    iconSecondary: 20,
    textTitle: 24,
    textBody: 19,
    textCaption: 13,
    controlHeight: 52,
    focusRingWidth: 4,
    panelRadius: 20,
    thumbWidth: 112,
    thumbHeight: 64,
    volumeTrackWidth: 160,
    minTextScale: 1.0,
    maxTextScale: 1.4,
  );

  static TvLayoutTokens forClass(TvWidthClass widthClass) => switch (widthClass) {
        TvWidthClass.compact => compact,
        TvWidthClass.normal => normal,
        TvWidthClass.big => big,
      };
}

/// Contexto adaptativo de exibicao (spec 27.3/27.4). Centraliza as
/// perguntas que as composicoes fazem: e TV? qual a classe de largura?
/// e ultrawide? qual a margem segura? Desktop nunca consulta tokens:
/// o desenho atual segue pixel a pixel.
abstract final class TvLayout {
  /// TV = Leanback detectado ou interruptor manual (resolvido na pref
  /// `tvMode` e publicado pelo [TvMode]).
  static bool isTv(BuildContext context) => TvMode.of(context);

  /// Classe pela largura logica (spec 27.4).
  static TvWidthClass widthClassOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 800) return TvWidthClass.compact;
    if (width < 1280) return TvWidthClass.normal;
    return TvWidthClass.big;
  }

  /// Ultrawide: proporcao acima de 1.90, somente desktop (spec 27.4).
  static bool isUltrawide(BuildContext context) {
    if (isTv(context)) return false;
    final size = MediaQuery.sizeOf(context);
    if (size.height <= 0) return false;
    return size.width / size.height > 1.90;
  }

  /// Margem segura anti-overscan (spec 27.5): 5% da menor dimensao
  /// util, entre 16 e 48. Numa TV 1080p (960x540 logico) = 27.
  static double safeMarginOf(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    return (shortest * 0.05).clamp(16.0, 48.0);
  }

  /// Tokens da classe atual. So faz sentido sob [isTv].
  static TvLayoutTokens tokensOf(BuildContext context) =>
      TvLayoutTokens.forClass(widthClassOf(context));

  /// Alvo minimo de toque: tokens na TV, 48 no celular, 44 no
  /// desktop (spec 3.4).
  static double minTarget(BuildContext context) {
    if (isTv(context)) return tokensOf(context).controlHeight;
    return MobileMode.of(context) ? MobileMode.minTouchTarget : 44.0;
  }

  /// Espaco base (paddings e gaps): fator por classe na TV, 1.0 fora.
  static double spacing(BuildContext context, double base) {
    if (!isTv(context)) return base;
    return switch (widthClassOf(context)) {
      TvWidthClass.compact => base * 1.25,
      TvWidthClass.normal => base * 1.5,
      TvWidthClass.big => base * 1.75,
    };
  }
}

/// Metricas reais da ultima barra TV desenhada (diagnostico).
/// O [TvPlayerControls] registra a cada layout; a tela de
/// diagnostico le sem reconstruir o player.
class TvPanelMetricsData {
  const TvPanelMetricsData({
    required this.constraints,
    required this.appliedMaxWidth,
  });

  /// Restricoes que o LayoutBuilder recebeu.
  final BoxConstraints constraints;

  /// Largura maxima calculada pelo perfil compacto.
  final double appliedMaxWidth;

  @override
  bool operator ==(Object other) =>
      other is TvPanelMetricsData &&
      other.constraints == constraints &&
      other.appliedMaxWidth == appliedMaxWidth;

  @override
  int get hashCode => Object.hash(constraints, appliedMaxWidth);
}

/// Registrador das metricas da barra TV.
abstract final class TvPanelMetrics {
  /// Ultimas metricas (null antes da primeira exibicao).
  static final ValueNotifier<TvPanelMetricsData?> current =
      ValueNotifier<TvPanelMetricsData?>(null);

  /// Guarda as metricas; so notifica quando mudam (o layout da
  /// barra nao reconstrui o diagnostico a toa).
  static void record(BoxConstraints constraints, double appliedMaxWidth) {
    final data = TvPanelMetricsData(
      constraints: constraints,
      appliedMaxWidth: appliedMaxWidth,
    );
    if (current.value != data) current.value = data;
  }

  /// Limpa o registro (testes).
  @visibleForTesting
  static void reset() => current.value = null;
}
