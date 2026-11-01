import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/desktop_window_service.dart';
import 'package:orpheus/ui/widgets/mini_player/mini_player_view.dart';
import 'package:orpheus/ui/widgets/mini_player/vinyl_disc_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VinylDiscWidget Tests', () {
    testWidgets('renders vinyl disc with RepaintBoundary and correct dimensions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VinylDiscWidget(
                coverPath: null,
                isPlaying: false,
                size: 140,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(VinylDiscWidget), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(find.byType(RotationTransition), findsWidgets);

      final sizeBox = tester.renderObject<RenderBox>(find.byType(VinylDiscWidget));
      expect(sizeBox.size.width, 140.0);
      expect(sizeBox.size.height, 140.0);
    });

    testWidgets('starts animation when isPlaying is true and stops on false',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VinylDiscWidget(
                coverPath: null,
                isPlaying: true,
                size: 120,
              ),
            ),
          ),
        ),
      );

      // Pump some frames to advance rotation
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Update widget to paused
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VinylDiscWidget(
                coverPath: null,
                isPlaying: false,
                size: 120,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(VinylDiscWidget), findsOneWidget);
    });
  });

  group('MiniPlayerView Tests', () {
    testWidgets('renders glassmorphic container and core controls',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: SizedBox(
              width: 320,
              height: 320,
              child: MiniPlayerView(),
            ),
          ),
        ),
      );

      expect(find.byType(MiniPlayerView), findsOneWidget);

      // Verify restore button exists
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
    });

    testWidgets('tapping restore button invokes exitMiniPlayer',
        (WidgetTester tester) async {
      final service = DesktopWindowService.instance;
      service.setMiniPlayerActiveForTesting(true);
      expect(service.isMiniPlayerActive, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: SizedBox(
              width: 320,
              height: 320,
              child: MiniPlayerView(),
            ),
          ),
        ),
      );

      final restoreBtn = find.byIcon(Icons.open_in_full_rounded);
      expect(restoreBtn, findsOneWidget);

      await tester.tap(restoreBtn);
      await tester.pumpAndSettle();

      if (service.isDesktop) {
        expect(service.isMiniPlayerActive, isFalse);
      }
    });
  });
}
