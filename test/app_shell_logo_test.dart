import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/app/mobile_mode.dart';
import 'package:player/app/tv_mode.dart';
import 'package:player/widgets/app_shell.dart';

Finder get _logo => find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(Image),
    );

Future<void> _pump(WidgetTester tester,
    {bool tv = false, bool mobile = false, bool logo = true}) async {
  await tester.pumpWidget(MaterialApp(
    home: MobileMode(
      enabled: mobile,
      child: TvMode(
        enabled: tv,
        child: AppShell(
          title: 'Olympus',
          showLogo: logo,
          body: const SizedBox(),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  for (final mode in const ['desktop', 'celular', 'TV']) {
    testWidgets('$mode: logo a esquerda do titulo', (tester) async {
      await _pump(tester, tv: mode == 'TV', mobile: mode == 'celular');

      final logo = tester.getRect(_logo);
      final title = tester.getRect(find.text('Olympus'));
      expect(logo.right, lessThanOrEqualTo(title.left));
      expect(logo.height, 28);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('telas comuns nao mostram a logo', (tester) async {
    await _pump(tester, logo: false);
    expect(_logo, findsNothing);
  });

  test('arquivo da logo esta no pacote', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load('assets/branding/olympus-mark.png');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
