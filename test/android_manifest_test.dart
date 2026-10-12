import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guarda do AndroidManifest: permissoes e entradas de TV que a validacao
/// em aparelho provou necessarias. Regressao real: sem INTERNET, todo link
/// http/https falhava com network.offline na TCL mesmo com ping OK.
void main() {
  test('manifest declara INTERNET, midia e entrada leanback', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.READ_MEDIA_VIDEO'));
    expect(manifest, contains('android.intent.category.LEANBACK_LAUNCHER'));
    expect(manifest, contains('@drawable/tv_banner'));
  });
}
