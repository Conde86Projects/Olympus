import 'package:flutter/material.dart';

/// Widgets de apoio do player (foco, cantos da TV, flash de seek e capa
/// de reposicionamento). Extraidos de player_screen.dart sem mudanca de
/// comportamento.

class PlayerTraversalPolicy extends ReadingOrderTraversalPolicy {
  PlayerTraversalPolicy({
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
class TvCornerIcons extends StatelessWidget {
  const TvCornerIcons({super.key, required this.tvMode, required this.child});

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
class SeekFlash extends StatelessWidget {
  const SeekFlash({super.key, required this.label, required this.left});

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
class RepositionCover extends StatelessWidget {
  const RepositionCover({super.key});

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
