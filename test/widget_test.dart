import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/services/audio_handler.dart';
import 'package:orpheus/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Mock path_provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );

    // Initialize database in temporary directory
    try {
      await LocalDatabase.instance.initialize();
    } catch (_) {}

    // Initialize audio handler instance for testing widgets
    if (!OrpheusAudioHandler.hasInstance) {
      OrpheusAudioHandler();
    }
  });

  testWidgets('OrpheusApp renders successfully', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const OrpheusApp());
      await tester.pump();

      // Verify logo is displayed in the sidebar on desktop
      expect(find.text('ORPHEUS'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
