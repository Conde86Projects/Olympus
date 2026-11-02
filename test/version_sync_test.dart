import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/constants/app_constants.dart';

void main() {
  test('a versão da tela é a mesma do pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
        .firstMatch(pubspec)!
        .group(1);

    expect(AppConstants.appVersion, version);
  });
}
