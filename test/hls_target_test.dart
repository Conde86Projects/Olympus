import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/utils/hls_target.dart';
import 'package:player/core/utils/hls_variants.dart';
import 'package:player/models/playback_state.dart';

const _master = 'https://cdn.exemplo.com/bbb/master.m3u8';
final _v720 = HlsVariant(
  uri: Uri.parse('https://cdn.exemplo.com/bbb/720.m3u8'),
  height: 720,
);
final _v360 = HlsVariant(
  uri: Uri.parse('https://cdn.exemplo.com/bbb/360.m3u8'),
  height: 360,
);
const _free = HlsAutoDecision(
  profile: HlsAutoProfile.desktop,
  capped: false,
);

void main() {
  group('isM3u8Url', () {
    test('reconhece playlist pelo caminho, sem depender de maiusculas', () {
      expect(isM3u8Url(_master), isTrue);
      expect(isM3u8Url('https://x.org/a/MASTER.M3U8?token=1'), isTrue);
    });

    test('nao confunde mp4 e URL invalida', () {
      expect(isM3u8Url('https://x.org/video.mp4'), isFalse);
      expect(isM3u8Url('::nao-url::'), isFalse);
    });
  });

  group('isLoadingStatus', () {
    test('carregando e buffer contam; o resto nao', () {
      expect(isLoadingStatus(PlaybackStatus.loading), isTrue);
      expect(isLoadingStatus(PlaybackStatus.buffering), isTrue);
      expect(isLoadingStatus(PlaybackStatus.playing), isFalse);
      expect(isLoadingStatus(PlaybackStatus.paused), isFalse);
    });
  });

  group('hlsTargetFor', () {
    test('Original sempre aponta para o master', () {
      expect(
        hlsTargetFor(HlsVariants.originalQualityId, _master, [_v720], _free),
        _master,
      );
    });

    test('variante conhecida vira a propria URL', () {
      final id = _v360.uri.toString();
      expect(hlsTargetFor(id, _master, [_v720, _v360], _free), id);
    });

    test('variante que sumiu do master cai na Automatica', () {
      expect(
        hlsTargetFor('https://sumiu.m3u8', _master, [_v720], _free),
        HlsVariants.automaticUrl(_master, [_v720], capped: false),
      );
    });

    test('Automatica sem teto usa o master', () {
      expect(
        hlsTargetFor(HlsVariants.autoQualityId, _master, [_v720], _free),
        _master,
      );
    });
  });
}
