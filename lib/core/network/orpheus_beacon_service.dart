import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../utils/debug_logger.dart';

/// Represents a remote or local Orpheus peer discovered on the LAN.
class DiscoveredNode {
  final String deviceId;
  final String deviceName;
  final String platform;
  final int port;
  final InternetAddress address;
  final String version;
  final DateTime lastSeen;

  DiscoveredNode({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.port,
    required this.address,
    required this.version,
    required this.lastSeen,
  });

  /// Base HTTP URL to communicate with this node's sync server.
  String get baseUrl => 'http://${address.address}:$port';

  /// Deserializes a beacon JSON payload received from [senderAddress].
  /// Returns `null` if the payload is invalid, malformed, or not an Orpheus beacon.
  static DiscoveredNode? parse({
    required List<int> rawBytes,
    required InternetAddress senderAddress,
    DateTime? timestamp,
  }) {
    try {
      final jsonString = utf8.decode(rawBytes);
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      if (decoded['service'] != OrpheusBeaconService.kServiceName) {
        return null;
      }

      final deviceId = decoded['device_id'] as String?;
      final deviceName = decoded['device_name'] as String?;
      final platform = decoded['platform'] as String?;
      final port = decoded['port'] as int?;
      final version = (decoded['version'] as String?) ?? '1.0.0';

      if (deviceId == null ||
          deviceId.trim().isEmpty ||
          deviceName == null ||
          platform == null ||
          port == null ||
          port <= 0 ||
          port > 65535) {
        return null;
      }

      return DiscoveredNode(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        port: port,
        address: senderAddress,
        version: version,
        lastSeen: timestamp ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes the beacon metadata into a JSON map.
  Map<String, dynamic> toJson() => {
        'service': OrpheusBeaconService.kServiceName,
        'version': version,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'port': port,
      };

  DiscoveredNode copyWith({
    String? deviceId,
    String? deviceName,
    String? platform,
    int? port,
    InternetAddress? address,
    String? version,
    DateTime? lastSeen,
  }) {
    return DiscoveredNode(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      port: port ?? this.port,
      address: address ?? this.address,
      version: version ?? this.version,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredNode &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          address.address == other.address.address &&
          port == other.port;

  @override
  int get hashCode =>
      deviceId.hashCode ^ address.address.hashCode ^ port.hashCode;

  @override
  String toString() =>
      'DiscoveredNode($deviceName [$platform] @ $baseUrl, id=$deviceId, seen=$lastSeen)';
}

/// UDP Beacon Discovery Service for Orpheus LAN synchronization.
///
/// Features:
/// - Announcement mode (Host/Desktop): Periodically broadcasts UDP beacons.
/// - Listening mode (Client/Mobile): Listens on the beacon port for active peers.
/// - Node lifecycle tracking and automatic expiration of inactive peers.
/// - Power management (pause/resume) for battery efficiency on mobile devices.
class OrpheusBeaconService {
  static const String kServiceName = 'orpheus-sync';
  static const String kProtocolVersion = '1.0.0';
  static const int kDefaultBeaconPort = 42424;
  static const Duration kDefaultBeaconInterval = Duration(seconds: 3);
  static const Duration kDefaultNodeTimeout = Duration(seconds: 10);

  final String deviceId;
  final String _customDeviceName;
  final String _customPlatform;
  final int serverPort;

  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _listeningSocket;

  Timer? _announcementTimer;
  Timer? _expirationTimer;

  bool _isAnnouncing = false;
  bool _isListening = false;
  bool _wasAnnouncingBeforePause = false;
  bool _wasListeningBeforePause = false;

  final Map<String, DiscoveredNode> _activeNodes = {};

  final StreamController<DiscoveredNode> _nodeDiscoveredController =
      StreamController<DiscoveredNode>.broadcast();
  final StreamController<List<DiscoveredNode>> _nodesChangedController =
      StreamController<List<DiscoveredNode>>.broadcast();

  OrpheusBeaconService({
    String? deviceId,
    String? deviceName,
    String? platform,
    this.serverPort = 50505,
  })  : deviceId = deviceId ?? _generateRandomDeviceId(),
        _customDeviceName = deviceName ?? '',
        _customPlatform = platform ?? '';

  /// Generates a pseudo-random hex identifier for the local device.
  static String _generateRandomDeviceId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Local device name.
  String get deviceName {
    if (_customDeviceName.trim().isNotEmpty) {
      return _customDeviceName;
    }
    return Platform.localHostname;
  }

  /// Local operating system/platform.
  String get platformName {
    if (_customPlatform.trim().isNotEmpty) {
      return _customPlatform;
    }
    return Platform.operatingSystem;
  }

  /// Whether announcement broadcasts are actively running.
  bool get isAnnouncing => _isAnnouncing;

  /// Whether UDP discovery listener is actively running.
  bool get isListening => _isListening;

  /// Stream of newly discovered or refreshed nodes.
  Stream<DiscoveredNode> get onNodeDiscovered =>
      _nodeDiscoveredController.stream;

  /// Stream of the full list of active LAN nodes whenever peers join or expire.
  Stream<List<DiscoveredNode>> get onNodesChanged =>
      _nodesChangedController.stream;

  /// Current snapshot of active, unexpired nodes.
  List<DiscoveredNode> get activeNodes =>
      List<DiscoveredNode>.unmodifiable(_activeNodes.values);

  // ── Announcement Mode (Host / Desktop) ───────────────────────────────────

  /// Starts emitting periodic UDP beacon packets to [broadcastAddress] on [beaconPort].
  Future<void> startAnnouncing({
    int beaconPort = kDefaultBeaconPort,
    Duration interval = kDefaultBeaconInterval,
    InternetAddress? broadcastAddress,
  }) async {
    if (_isAnnouncing) return;

    try {
      _broadcastSocket ??= await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // Ephemeral sending port
        reuseAddress: true,
        reusePort: true,
      );
      _broadcastSocket!.broadcastEnabled = true;

      _isAnnouncing = true;
      DebugLogger.log(
        'OrpheusBeaconService: Started announcing as "$deviceName" ($deviceId) on port $beaconPort',
      );

      final targetAddress = broadcastAddress ?? InternetAddress('255.255.255.255');

      // Send initial broadcast immediately
      _sendBeacon(targetAddress, beaconPort);

      // Schedule periodic broadcasts
      _announcementTimer?.cancel();
      _announcementTimer = Timer.periodic(interval, (_) {
        _sendBeacon(targetAddress, beaconPort);
      });
    } catch (e, stack) {
      DebugLogger.log('OrpheusBeaconService: Failed to start announcing: $e\n$stack');
      _isAnnouncing = false;
      rethrow;
    }
  }

  /// Stops emitting UDP announcements and releases the sender socket.
  void stopAnnouncing() {
    _announcementTimer?.cancel();
    _announcementTimer = null;
    _isAnnouncing = false;

    if (_broadcastSocket != null) {
      try {
        _broadcastSocket!.close();
      } catch (_) {}
      _broadcastSocket = null;
    }
    DebugLogger.log('OrpheusBeaconService: Stopped announcing');
  }

  /// Encodes and sends a single beacon packet.
  void _sendBeacon(InternetAddress destination, int port) {
    if (!_isAnnouncing || _broadcastSocket == null) return;

    try {
      final payload = {
        'service': kServiceName,
        'version': kProtocolVersion,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platformName,
        'port': serverPort,
      };

      final data = utf8.encode(jsonEncode(payload));
      _broadcastSocket!.send(data, destination, port);
    } catch (e) {
      DebugLogger.log('OrpheusBeaconService: Error sending beacon: $e');
    }
  }

  // ── Listening Mode (Client / Mobile) ─────────────────────────────────────

  /// Starts listening for LAN beacon announcements on [beaconPort].
  Future<void> startListening({
    int beaconPort = kDefaultBeaconPort,
    Duration nodeTimeout = kDefaultNodeTimeout,
    InternetAddress? bindAddress,
  }) async {
    if (_isListening) return;

    try {
      final addressToBind = bindAddress ?? InternetAddress.anyIPv4;
      _listeningSocket = await RawDatagramSocket.bind(
        addressToBind,
        beaconPort,
        reuseAddress: true,
        reusePort: true,
      );
      _listeningSocket!.broadcastEnabled = true;

      _isListening = true;
      DebugLogger.log(
        'OrpheusBeaconService: Listening for peers on port $beaconPort',
      );

      _listeningSocket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            _handleIncomingDatagram();
          }
        },
        onError: (e, stack) {
          DebugLogger.log('OrpheusBeaconService: Socket listen error: $e');
        },
        onDone: () {
          _isListening = false;
        },
        cancelOnError: false,
      );

      // Start periodic sweep to remove dead peers
      _expirationTimer?.cancel();
      _expirationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _purgeExpiredNodes(nodeTimeout);
      });
    } catch (e, stack) {
      DebugLogger.log('OrpheusBeaconService: Failed to bind listening socket on port $beaconPort: $e\n$stack');
      _isListening = false;
      rethrow;
    }
  }

  /// Stops listening for peers and releases the socket.
  void stopListening() {
    _expirationTimer?.cancel();
    _expirationTimer = null;
    _isListening = false;

    if (_listeningSocket != null) {
      try {
        _listeningSocket!.close();
      } catch (_) {}
      _listeningSocket = null;
    }
    DebugLogger.log('OrpheusBeaconService: Stopped listening');
  }

  /// Reads and processes available datagrams from the listening socket.
  void _handleIncomingDatagram() {
    final socket = _listeningSocket;
    if (socket == null) return;

    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      try {
        final node = DiscoveredNode.parse(
          rawBytes: datagram!.data,
          senderAddress: datagram.address,
        );

        if (node == null) continue;

        // Ignore announcements from our own device
        if (node.deviceId == deviceId) continue;

        final isNew = !_activeNodes.containsKey(node.deviceId);
        _activeNodes[node.deviceId] = node;

        if (isNew) {
          DebugLogger.log(
            'OrpheusBeaconService: Discovered new peer: ${node.deviceName} (${node.baseUrl})',
          );
        }

        if (!_nodeDiscoveredController.isClosed) {
          _nodeDiscoveredController.add(node);
        }
        _notifyNodesChanged();
      } catch (e) {
        DebugLogger.log('OrpheusBeaconService: Error processing datagram: $e');
      }
    }
  }

  /// Removes nodes that haven't sent a beacon within [timeout].
  void _purgeExpiredNodes(Duration timeout) {
    if (_activeNodes.isEmpty) return;

    final now = DateTime.now();
    final expiredIds = <String>[];

    for (final entry in _activeNodes.entries) {
      if (now.difference(entry.value.lastSeen) > timeout) {
        expiredIds.add(entry.key);
      }
    }

    if (expiredIds.isNotEmpty) {
      for (final id in expiredIds) {
        final node = _activeNodes.remove(id);
        DebugLogger.log(
          'OrpheusBeaconService: Node expired: ${node?.deviceName} ($id)',
        );
      }
      _notifyNodesChanged();
    }
  }

  void _notifyNodesChanged() {
    if (!_nodesChangedController.isClosed) {
      _nodesChangedController.add(activeNodes);
    }
  }

  // ── Lifecycle & Power Management ──────────────────────────────────────────

  /// Pauses advertising and discovery to conserve battery on mobile devices.
  void pause() {
    _wasAnnouncingBeforePause = _isAnnouncing;
    _wasListeningBeforePause = _isListening;

    if (_isAnnouncing) {
      stopAnnouncing();
    }
    if (_isListening) {
      stopListening();
    }
    DebugLogger.log('OrpheusBeaconService: Paused');
  }

  /// Resumes advertising and discovery if they were active before pausing.
  Future<void> resume({
    int beaconPort = kDefaultBeaconPort,
    Duration interval = kDefaultBeaconInterval,
    Duration nodeTimeout = kDefaultNodeTimeout,
  }) async {
    DebugLogger.log('OrpheusBeaconService: Resuming...');
    if (_wasAnnouncingBeforePause) {
      await startAnnouncing(beaconPort: beaconPort, interval: interval);
    }
    if (_wasListeningBeforePause) {
      await startListening(beaconPort: beaconPort, nodeTimeout: nodeTimeout);
    }
  }

  /// Cleans up all sockets, timers, and broadcast stream controllers.
  Future<void> dispose() async {
    stopAnnouncing();
    stopListening();
    _activeNodes.clear();

    await _nodeDiscoveredController.close();
    await _nodesChangedController.close();
  }
}
