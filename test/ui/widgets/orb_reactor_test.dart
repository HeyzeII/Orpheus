import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/ui/widgets/orb_reactor/central_orb_disc.dart';
import 'package:orpheus/ui/widgets/orb_reactor/orb_transport_controls.dart';
import 'package:orpheus/ui/widgets/orb_reactor/reactor_waves_painter.dart';
import 'package:orpheus/ui/widgets/orb_reactor/volume_energy_stack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Orb Reactor Unit & Widget Tests', () {
    test('ReactorWavesPainter shouldRepaint triggers correctly on state change', () {
      final painter1 = ReactorWavesPainter(
        animationValue: 0.2,
        isPlaying: true,
      );
      final painter2 = ReactorWavesPainter(
        animationValue: 0.2,
        isPlaying: true,
      );
      final painter3 = ReactorWavesPainter(
        animationValue: 0.5,
        isPlaying: true,
      );
      final painter4 = ReactorWavesPainter(
        animationValue: 0.2,
        isPlaying: false,
      );

      expect(painter1.shouldRepaint(painter2), isFalse);
      expect(painter1.shouldRepaint(painter3), isTrue);
      expect(painter1.shouldRepaint(painter4), isTrue);
    });

    test('ReactorWavesPainter paints valid paths on Canvas without errors', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = ReactorWavesPainter(
        animationValue: 0.35,
        isPlaying: true,
      );

      // Paint at standard size (250x250)
      expect(() => painter.paint(canvas, const Size(250, 250)), returnsNormally);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    testWidgets('VolumeEnergyStack renders vertical battery segments and volume icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VolumeEnergyStack(
                width: 24,
                height: 100,
                segments: 6,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(VolumeEnergyStack), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('CentralOrbDisc mounts and displays with rotation controller', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CentralOrbDisc(
                coverPath: null,
                isPlaying: true,
                size: 120,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CentralOrbDisc), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('OrbHeaderRow renders track title and action buttons', (tester) async {
      final sampleTrack = Track()
        ..trackId = 'orb-test-1'
        ..title = 'Cyberpunk Odyssey'
        ..artist = 'Orpheus Reactor';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrbHeaderRow(track: sampleTrack),
          ),
        ),
      );

      expect(find.text('Cyberpunk Odyssey'), findsOneWidget);
      expect(find.text('Orpheus Reactor'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
    });
  });
}
