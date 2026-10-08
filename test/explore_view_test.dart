import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/services/audio_handler.dart';
import 'package:orpheus/ui/views/explore_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') return ['wifi'];
        return null;
      },
    );

    try {
      await LocalDatabase.instance.initialize();
    } catch (_) {}

    if (!OrpheusAudioHandler.hasInstance) {
      OrpheusAudioHandler();
    }
  });

  group('ExploreView Widget Tests', () {
    testWidgets('Renders empty state or main explore screen gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExploreView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check if empty state or explore header is rendered
      final hasEmpty = find.text('Sin pistas para explorar').evaluate().isNotEmpty;
      final hasHeader = find.text('EXPLORAR').evaluate().isNotEmpty;

      expect(hasEmpty || hasHeader, isTrue);
    });
  });
}
