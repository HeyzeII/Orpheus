import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/network/orpheus_beacon_service.dart';

void main() {
  group('DiscoveredNode Parsing and Model', () {
    final senderIp = InternetAddress('192.168.1.100');

    test('parses valid beacon JSON correctly', () {
      final validJson = jsonEncode({
        'service': 'orpheus-sync',
        'version': '1.0.0',
        'device_id': 'fedora-desktop-uuid-42',
        'device_name': 'Aldo-Fedora-Workstation',
        'platform': 'linux',
        'port': 50505,
      });

      final node = DiscoveredNode.parse(
        rawBytes: utf8.encode(validJson),
        senderAddress: senderIp,
      );

      expect(node, isNotNull);
      expect(node!.deviceId, equals('fedora-desktop-uuid-42'));
      expect(node.deviceName, equals('Aldo-Fedora-Workstation'));
      expect(node.platform, equals('linux'));
      expect(node.port, equals(50505));
      expect(node.address.address, equals('192.168.1.100'));
      expect(node.version, equals('1.0.0'));
      expect(node.baseUrl, equals('http://192.168.1.100:50505'));
    });

    test('serializes back to JSON matching spec format', () {
      final node = DiscoveredNode(
        deviceId: 'macbook-uuid-99',
        deviceName: 'Aldo-MacBook',
        platform: 'macos',
        port: 50505,
        address: senderIp,
        version: '1.0.0',
        lastSeen: DateTime(2026, 10, 24),
      );

      final json = node.toJson();
      expect(json['service'], equals('orpheus-sync'));
      expect(json['version'], equals('1.0.0'));
      expect(json['device_id'], equals('macbook-uuid-99'));
      expect(json['device_name'], equals('Aldo-MacBook'));
      expect(json['platform'], equals('macos'));
      expect(json['port'], equals(50505));
    });

    test('discards non-orpheus services', () {
      final invalidJson = jsonEncode({
        'service': 'other-service',
        'version': '1.0.0',
        'device_id': 'some-id',
        'device_name': 'Some-Device',
        'platform': 'android',
        'port': 8080,
      });

      final node = DiscoveredNode.parse(
        rawBytes: utf8.encode(invalidJson),
        senderAddress: senderIp,
      );

      expect(node, isNull);
    });

    test('discards malformed JSON string or invalid byte sequence', () {
      final node = DiscoveredNode.parse(
        rawBytes: [0xFF, 0xFE, 0x00],
        senderAddress: senderIp,
      );
      expect(node, isNull);

      final malformedNode = DiscoveredNode.parse(
        rawBytes: utf8.encode('{ "service": "orpheus-sync", incomplete...'),
        senderAddress: senderIp,
      );
      expect(malformedNode, isNull);
    });

    test('discards payload missing mandatory fields or invalid port', () {
      final missingFields = jsonEncode({
        'service': 'orpheus-sync',
        'device_name': 'Incomplete-Device',
      });
      expect(
        DiscoveredNode.parse(
          rawBytes: utf8.encode(missingFields),
          senderAddress: senderIp,
        ),
        isNull,
      );

      final invalidPortJson = jsonEncode({
        'service': 'orpheus-sync',
        'device_id': 'id-1',
        'device_name': 'Dev',
        'platform': 'linux',
        'port': -5,
      });
      expect(
        DiscoveredNode.parse(
          rawBytes: utf8.encode(invalidPortJson),
          senderAddress: senderIp,
        ),
        isNull,
      );

      final portTooHighJson = jsonEncode({
        'service': 'orpheus-sync',
        'device_id': 'id-1',
        'device_name': 'Dev',
        'platform': 'linux',
        'port': 70000,
      });
      expect(
        DiscoveredNode.parse(
          rawBytes: utf8.encode(portTooHighJson),
          senderAddress: senderIp,
        ),
        isNull,
      );
    });
  });

  group('OrpheusBeaconService Discovery Lifecycle & Networking', () {
    const testPort = 42499;

    test('filters out announcements from own deviceId', () async {
      final service = OrpheusBeaconService(
        deviceId: 'self-device-123',
        deviceName: 'Self-Node',
        platform: 'linux',
      );

      await service.startListening(
        beaconPort: testPort,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      bool emitted = false;
      service.onNodeDiscovered.listen((_) => emitted = true);

      // Simulate sending own beacon to listener
      final ownPayload = jsonEncode({
        'service': 'orpheus-sync',
        'version': '1.0.0',
        'device_id': 'self-device-123',
        'device_name': 'Self-Node',
        'platform': 'linux',
        'port': 50505,
      });

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.send(
        utf8.encode(ownPayload),
        InternetAddress.loopbackIPv4,
        testPort,
      );
      sender.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emitted, isFalse);
      expect(service.activeNodes, isEmpty);

      await service.dispose();
    });

    test('discovers remote peer over loopback datagram socket', () async {
      final listenerService = OrpheusBeaconService(
        deviceId: 'client-phone-id',
        deviceName: 'Android-Pixel-8',
        platform: 'android',
      );

      final hostService = OrpheusBeaconService(
        deviceId: 'server-desktop-id',
        deviceName: 'Fedora-Desktop',
        platform: 'linux',
        serverPort: 50505,
      );

      await listenerService.startListening(
        beaconPort: testPort + 1,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      final discoveredFuture = listenerService.onNodeDiscovered.first;

      await hostService.startAnnouncing(
        beaconPort: testPort + 1,
        broadcastAddress: InternetAddress.loopbackIPv4,
        interval: const Duration(milliseconds: 500),
      );

      final discovered = await discoveredFuture.timeout(
        const Duration(seconds: 3),
      );

      expect(discovered.deviceId, equals('server-desktop-id'));
      expect(discovered.deviceName, equals('Fedora-Desktop'));
      expect(discovered.platform, equals('linux'));
      expect(discovered.port, equals(50505));
      expect(listenerService.activeNodes.length, equals(1));

      await hostService.dispose();
      await listenerService.dispose();
    });

    test('purges expired nodes after timeout', () async {
      final service = OrpheusBeaconService(
        deviceId: 'manager-id',
        deviceName: 'Manager',
        platform: 'macos',
      );

      await service.startListening(
        beaconPort: testPort + 2,
        bindAddress: InternetAddress.loopbackIPv4,
        nodeTimeout: const Duration(milliseconds: 200),
      );

      // Send a single beacon from an external peer
      final peerPayload = jsonEncode({
        'service': 'orpheus-sync',
        'version': '1.0.0',
        'device_id': 'temporary-peer-id',
        'device_name': 'Temp-Peer',
        'platform': 'android',
        'port': 50505,
      });

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.send(
        utf8.encode(peerPayload),
        InternetAddress.loopbackIPv4,
        testPort + 2,
      );
      sender.close();

      await service.onNodeDiscovered.first;
      expect(service.activeNodes.length, equals(1));

      // Wait past nodeTimeout + sweep interval (sweep is every 2 seconds, wait 2.5s)
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      expect(service.activeNodes, isEmpty);

      await service.dispose();
    });

    test('pause and resume lifecycle controls discovery and announcement', () async {
      final service = OrpheusBeaconService(
        deviceId: 'lifecycle-device',
        deviceName: 'Tester',
        platform: 'linux',
      );

      await service.startListening(
        beaconPort: testPort + 3,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await service.startAnnouncing(
        beaconPort: testPort + 3,
        broadcastAddress: InternetAddress.loopbackIPv4,
      );

      expect(service.isListening, isTrue);
      expect(service.isAnnouncing, isTrue);

      service.pause();
      expect(service.isListening, isFalse);
      expect(service.isAnnouncing, isFalse);

      await service.resume(beaconPort: testPort + 3);
      expect(service.isListening, isTrue);
      expect(service.isAnnouncing, isTrue);

      await service.dispose();
      expect(service.isListening, isFalse);
      expect(service.isAnnouncing, isFalse);
    });
  });
}
