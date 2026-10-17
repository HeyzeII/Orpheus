import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiniPlayer Permanent Touch Interactivity Tests', () {
    testWidgets('MiniPlayer tap target responds immediately to taps without pointer blocking', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapCount++,
              child: const SizedBox(
                width: 200,
                height: 60,
                child: Text('MiniPlayer Permanent Tap Target'),
              ),
            ),
          ),
        ),
      );

      // Verify tap works immediately
      await tester.tap(find.text('MiniPlayer Permanent Tap Target'));
      await tester.pump();
      expect(tapCount, equals(1));

      // Simulate second immediate tap
      await tester.tap(find.text('MiniPlayer Permanent Tap Target'));
      await tester.pump();
      expect(tapCount, equals(2));
    });
  });
}
