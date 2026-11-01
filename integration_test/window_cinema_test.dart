import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:player/services/window_service.dart';
import 'package:window_manager/window_manager.dart';

/// Janela real do Windows: esconder a barra de titulo do modo cinema nao
/// move nem redimensiona a janela, tambem numa divisao da tela e depois de
/// passar pela tela cheia.
///
/// Rodar com: `flutter test -d windows integration_test/window_cinema_test.dart`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('barra do cinema some e volta com a janela no lugar',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final windows = WindowManagerService();
    await windows.applyStartupGeometry(
      title: 'Teste do cinema',
      alwaysOnTop: false,
      startInFullscreen: false,
    );

    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    }

    double clientHeight() =>
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // Um quarto de um monitor de 2752x1152 (ultrawide com escala 125%).
    const quarter = Rect.fromLTWH(100, 100, 1376, 552);
    await windowManager.setBounds(quarter);
    await settle();
    final before = await windowManager.getBounds();
    final withBar = clientHeight();

    await windows.setTitleBarHidden(true);
    await settle();
    expect(await windowManager.getBounds(), before);
    final withoutBar = clientHeight();
    expect(withoutBar, greaterThan(withBar + 20),
        reason: 'o video ganha a altura da barra');

    await windows.setFullscreen(true);
    await settle();
    await windows.setFullscreen(false);
    await settle();
    expect(await windowManager.getBounds(), before);
    expect(clientHeight(), withoutBar, reason: 'segue sem barra');

    await windows.setTitleBarHidden(false);
    await settle();
    expect(await windowManager.getBounds(), before);
    expect(clientHeight(), withBar);
  });
}
