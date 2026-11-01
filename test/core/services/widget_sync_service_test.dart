import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (call) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('es.antonborri.home_widget'), (call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('es.antonborri.home_widget'), null);
  });

  group('WidgetSyncService Tests', () {
    test('Initialization and disposal work cleanly without leaking streams', () {
      final service = WidgetSyncService.instance;
      expect(service.isInitialized, isFalse);

      service.initialize();
      expect(service.isInitialized, isTrue);

      // Calling initialize again should be idempotent
      service.initialize();
      expect(service.isInitialized, isTrue);

      service.dispose();
      expect(service.isInitialized, isFalse);
    });

    test('androidWidgetProvider and androidCompactWidgetProvider match expected values', () {
      expect(WidgetSyncService.androidWidgetProvider, equals('OrpheusWidgetProvider'));
      expect(WidgetSyncService.androidCompactWidgetProvider, equals('OrpheusCompactWidgetProvider'));
    });
  });
}
