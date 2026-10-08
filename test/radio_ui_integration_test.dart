import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/audio_player_service.dart';
import 'package:orpheus/ui/widgets/radio_indicator_badge.dart';
import 'package:orpheus/ui/widgets/mood_picker_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RadioIndicatorBadge Widget Tests', () {
    testWidgets('Renders nothing when isRadioActive is false', (tester) async {
      AudioPlayerService.isRadioActiveNotifier.value = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RadioIndicatorBadge(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RADIO'), findsNothing);
      expect(find.byIcon(Icons.radio_rounded), findsNothing);
    });

    testWidgets('Renders badge with icon and text when isRadioActive is true', (tester) async {
      AudioPlayerService.isRadioActiveNotifier.value = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RadioIndicatorBadge(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RADIO'), findsOneWidget);
      expect(find.byIcon(Icons.radio_rounded), findsOneWidget);
    });
  });

  group('MoodPickerWidget Widget Tests', () {
    testWidgets('Renders mood picker header, sliders, and action button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodPickerWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header
      expect(find.text('SESIÓN POR ÁNIMO'), findsOneWidget);

      // Check slider labels
      expect(find.text('Energía'), findsOneWidget);
      expect(find.text('Ritmo'), findsOneWidget);
      expect(find.text('Brillo'), findsOneWidget);

      // Check preset chips
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Chill'), findsOneWidget);
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Acústico'), findsOneWidget);

      // Check action button
      expect(find.text('Crear Sesión'), findsOneWidget);
    });

    testWidgets('Tapping preset chip applies mood preset percentages', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoodPickerWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Workout preset
      await tester.tap(find.text('Workout'));
      await tester.pumpAndSettle();

      // Energy 90%
      expect(find.text('90%'), findsOneWidget);
      // Density 85%
      expect(find.text('85%'), findsOneWidget);
    });
  });
}
