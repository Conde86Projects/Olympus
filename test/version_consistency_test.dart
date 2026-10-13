import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/constants/app_constants.dart';

/// Trava de release: a versão exibida no diagnóstico acompanha o
/// núcleo do `version:` do pubspec (sem o build). Evita repetir o
/// caso em que o aparelho mostrava uma RC antiga na tela e no
/// relatório exportado.
void main() {
  test('AppConstants.appVersion acompanha o pubspec', () {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final raw = lines
        .firstWhere((l) => l.startsWith('version:'))
        .split(':')
        .last
        .trim();
    final core = raw.split('+').first;
    expect(AppConstants.appVersion, core);
  });
}
