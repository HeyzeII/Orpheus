import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/desktop_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopWindowService Tests', () {
    late DesktopWindowService service;

    setUp(() {
      service = DesktopWindowService.instance;
      service.setMiniPlayerActiveForTesting(false);
    });

    tearDown(() {
      service.setMiniPlayerActiveForTesting(false);
    });

    test('initializes with mini player inactive and correct target dimensions', () {
      expect(service.isMiniPlayerActive, isFalse);
      expect(service.isMiniPlayerNotifier.value, isFalse);
      expect(DesktopWindowService.kMiniPlayerSize.width, 320.0);
      expect(DesktopWindowService.kMiniPlayerSize.height, 320.0);
      expect(DesktopWindowService.kMiniPlayerMinSize.width, 280.0);
      expect(DesktopWindowService.kMiniPlayerMinSize.height, 280.0);
      expect(DesktopWindowService.kStandardMinSize.width, 950.0);
      expect(DesktopWindowService.kStandardMinSize.height, 650.0);
    });

    test('setMiniPlayerActiveForTesting updates notifier and active getter', () {
      bool notified = false;
      service.isMiniPlayerNotifier.addListener(() {
        notified = true;
      });

      service.setMiniPlayerActiveForTesting(true);
      expect(service.isMiniPlayerActive, isTrue);
      expect(notified, isTrue);

      service.setMiniPlayerActiveForTesting(false);
      expect(service.isMiniPlayerActive, isFalse);
    });

    test('toggleMiniPlayer alternates states properly', () async {
      expect(service.isMiniPlayerActive, isFalse);
      await service.toggleMiniPlayer();
      // On desktop platforms, enterMiniPlayer sets state to true
      if (service.isDesktop) {
        expect(service.isMiniPlayerActive, isTrue);
        await service.toggleMiniPlayer();
        expect(service.isMiniPlayerActive, isFalse);
      }
    });

    test('exitMiniPlayer restores state when active', () async {
      service.setMiniPlayerActiveForTesting(true);
      expect(service.isMiniPlayerActive, isTrue);

      if (service.isDesktop) {
        await service.exitMiniPlayer();
        expect(service.isMiniPlayerActive, isFalse);
      }
    });
  });
}
