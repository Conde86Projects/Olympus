import 'package:flutter/widgets.dart';
import 'package:player/app/routes.dart';

/// Destinos a que uma tela pode levar de qualquer ponto
/// (hoje: as saidas do fim do video).
enum ExitTarget { home, library }

/// Leva a um destino principal. No computador e na TV, desfaz a pilha
/// ate o Inicio e abre a tela pedida; no celular, a pilha volta ao
/// [MobileShell] e o pedido em [request] troca a aba.
abstract final class MainNavigation {
  /// Pedido de aba para o celular; o [MobileShell] consome e zera.
  static final ValueNotifier<ExitTarget?> request = ValueNotifier(null);

  static void go(
    NavigatorState navigator,
    ExitTarget target, {
    required bool mobile,
  }) {
    navigator.popUntil(
        (route) => route.isFirst || route.settings.name == AppRoutes.home);
    if (mobile) {
      request.value = target;
    } else if (target == ExitTarget.library) {
      navigator.pushNamed(AppRoutes.library);
    }
  }
}
