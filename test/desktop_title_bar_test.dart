import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/ui/widgets/desktop_title_bar.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopTitleBar Widget Tests', () {
    testWidgets('renders correctly with 36px height and branding text',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );

      // Verify DesktopTitleBar preferred size height is 36.0
      expect(DesktopTitleBar.kHeight, 36.0);
      expect(find.byType(DesktopTitleBar), findsOneWidget);

      // Verify Orpheus title text is rendered
      expect(find.text('Orpheus'), findsOneWidget);

      // Verify DragToMoveArea exists for window movement
      expect(find.byType(DragToMoveArea), findsWidgets);
    });

    testWidgets('double-tap on title bar drag area does not throw',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopTitleBar(),
          ),
        ),
      );

      // Find the center title text and double tap
      final centerTitle = find.text('Orpheus');
      expect(centerTitle, findsOneWidget);

      // Double tap on the center region
      await tester.tap(centerTitle);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(centerTitle);
      await tester.pumpAndSettle();
    });
  });
}
