import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
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
  });

  testWidgets('OrpheusApp renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const OrpheusApp());
    await tester.pump();

    // Verify logo is displayed in the sidebar
    expect(find.text('ORPHEUS'), findsOneWidget);
  });
}
