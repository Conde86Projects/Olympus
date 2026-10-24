import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/mobile_chrome_service.dart';

class FakeMobileChrome extends MobileChromeService {
  bool _fullscreen = false;
  final List<bool> calls = [];

  @override
  bool get isFullscreen => _fullscreen;

  @override
  Future<void> setFullscreen(bool enabled) async {
    calls.add(enabled);
    if (_fullscreen == enabled) return;
    _fullscreen = enabled;
    notifyListeners();
  }
}

void main() {
  group('MobileChrome (fake)', () {
    test('entra e sai da cheia notificando uma vez por mudanca', () async {
      final chrome = FakeMobileChrome();
      var calls = 0;
      chrome.addListener(() => calls++);

      expect(chrome.isFullscreen, isFalse);

      await chrome.setFullscreen(true);
      expect(chrome.isFullscreen, isTrue);
      expect(calls, 1);

      await chrome.setFullscreen(false);
      expect(chrome.isFullscreen, isFalse);
      expect(calls, 2);
    });

    test('chamada repetida nao renotifica', () async {
      final chrome = FakeMobileChrome();
      var calls = 0;
      chrome.addListener(() => calls++);

      await chrome.setFullscreen(true);
      await chrome.setFullscreen(true);

      expect(chrome.isFullscreen, isTrue);
      expect(chrome.calls, [true, true]);
      expect(calls, 1);
    });
  });
}
