import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/app_navigation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppNavigationCoordinator Gesture Lock Tests', () {
    testWidgets('triggerMiniPlayerGestureLock activates and resets after post frame callback', (tester) async {
      final coordinator = AppNavigationCoordinator.instance;
      coordinator.miniPlayerPointerBlocked.value = false;

      await tester.pumpWidget(const SizedBox());
      expect(coordinator.miniPlayerPointerBlocked.value, isFalse);

      coordinator.triggerMiniPlayerGestureLock();
      expect(coordinator.miniPlayerPointerBlocked.value, isTrue);

      // Pump a frame so the post-frame callback runs
      await tester.pump();
      expect(coordinator.miniPlayerPointerBlocked.value, isFalse);
    });

    testWidgets('ValueListenableBuilder with miniPlayerPointerBlocked toggles IgnorePointer', (tester) async {
      final coordinator = AppNavigationCoordinator.instance;
      coordinator.miniPlayerPointerBlocked.value = false;
      int tapCount = 0;
      const ignorePointerKey = Key('mini_player_lock_ignore_pointer');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: coordinator.miniPlayerPointerBlocked,
              builder: (context, isBlocked, child) {
                return IgnorePointer(
                  key: ignorePointerKey,
                  ignoring: isBlocked,
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: () => tapCount++,
                child: const Text('MiniPlayer Tap Target'),
              ),
            ),
          ),
        ),
      );

      // Verify normal tap works
      await tester.tap(find.text('MiniPlayer Tap Target'));
      await tester.pump();
      expect(tapCount, equals(1));

      // Trigger gesture lock
      coordinator.triggerMiniPlayerGestureLock();
      // Pump without advancing frame to check active lock state
      await tester.pump(Duration.zero);

      // Verify IgnorePointer widget is ignoring
      final ignorePointer = tester.widget<IgnorePointer>(find.byKey(ignorePointerKey));
      expect(ignorePointer.ignoring, isTrue);

      // Once the frame completes, lock is released
      await tester.pump();
      expect(coordinator.miniPlayerPointerBlocked.value, isFalse);

      final ignorePointerAfter = tester.widget<IgnorePointer>(find.byKey(ignorePointerKey));
      expect(ignorePointerAfter.ignoring, isFalse);

      await tester.tap(find.text('MiniPlayer Tap Target'));
      await tester.pump();
      expect(tapCount, equals(2));
    });
  });
}
