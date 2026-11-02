import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/progress_save_policy.dart';
import 'package:player/models/playback_state.dart';

const _minute = Duration(minutes: 1);
const _film = Duration(minutes: 90);

bool decide({
  bool remember = true,
  PlaybackStatus status = PlaybackStatus.playing,
  Duration position = Duration.zero,
  Duration? duration = _film,
  Duration? saved,
  bool saw = false,
  bool replay = false,
}) =>
    shouldSaveProgress(
      rememberPosition: remember,
      status: status,
      position: position,
      duration: duration,
      savedPosition: saved,
      sawPosition: saw,
      openedCompleted: replay,
    );

void main() {
  test('com "lembrar posição" desligado, nunca salva', () {
    expect(decide(remember: false, position: _minute, saw: true), isFalse);
  });

  test('assistiu um trecho: salva', () {
    expect(decide(position: _minute, saved: _minute * 2, saw: true), isTrue);
  });

  test('saiu antes de chegar ao ponto salvo: mantém o ponto', () {
    expect(decide(saved: _minute * 5), isFalse);
  });

  test('voltou ao zero depois de assistir: salva o zero', () {
    expect(decide(saved: _minute * 5, saw: true), isTrue);
  });

  test('estreia sem progresso registra a visita', () {
    expect(decide(), isTrue);
  });

  test('falhou sem tocar: não registra nada', () {
    expect(decide(status: PlaybackStatus.error), isFalse);
    expect(decide(status: PlaybackStatus.error, saved: _minute), isFalse);
  });

  test('erro depois de tocar guarda o que foi visto', () {
    expect(
      decide(status: PlaybackStatus.error, position: _minute, saw: true),
      isTrue,
    );
  });

  test('replay de concluído parado no zero não muda nada', () {
    expect(decide(saved: _film, saw: true, replay: true), isFalse);
  });

  test('sem duração e parado no zero não sobrescreve a retomada', () {
    expect(decide(duration: null, saved: _minute, saw: true), isFalse);
  });
}
