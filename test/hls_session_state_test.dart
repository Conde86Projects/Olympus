import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/features/player/hls_session_state.dart';

void main() {
  test('estado inicial: automatica, sem variante efetiva, sem protecao', () {
    final state = HlsSessionState();
    expect(state.quality.value, HlsVariants.autoQualityId);
    expect(state.effective.value, isNull);
    expect(state.positionProtect, isFalse);
    state.dispose();
  });

  test('nova fonte volta ao estado inicial', () {
    final state = HlsSessionState();
    state.quality.value = '720p';
    state.effective.value = 'https://x/720.m3u8';
    state.positionProtect = true;

    state.resetForNewSource();

    expect(state.quality.value, HlsVariants.autoQualityId);
    expect(state.effective.value, isNull);
    expect(state.positionProtect, isFalse);
    state.dispose();
  });

  test('notificadores avisam quem esta ouvindo', () {
    final state = HlsSessionState();
    final seen = <String>[];
    state.quality.addListener(() => seen.add(state.quality.value));
    state.quality.value = '360p';
    expect(seen, ['360p']);
    state.dispose();
  });
}
