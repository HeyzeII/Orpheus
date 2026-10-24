import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/custom_metadata.dart';
import '../models/track.dart';
import '../utils/debug_logger.dart';
import 'local_sync_server.dart';
import 'orpheus_beacon_service.dart';

/// Exception thrown by [LocalSyncClient] when an HTTP or parsing error occurs.
class LocalSyncClientException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  LocalSyncClientException(this.message, {this.statusCode, this.cause});

  @override
  String toString() {
    if (statusCode != null) {
      return 'LocalSyncClientException (HTTP $statusCode): $message';
    }
    return 'LocalSyncClientException: $message';
  }
}

/// Structured response from an Orpheus node ping endpoint (`/api/v1/ping`).
class NodePingResponse {
  final String status;
  final String service;
  final String version;
  final String deviceName;
  final String platform;
  final int port;
  final DateTime? timestamp;
  final Map<String, dynamic> raw;

  /// Returns `true` if the node responded with healthy status and the Orpheus service identifier.
  bool get isOk => status == 'ok' && service == 'orpheus-sync';

  NodePingResponse({
    required this.status,
    required this.service,
    required this.version,
    required this.deviceName,
    required this.platform,
    required this.port,
    this.timestamp,
    this.raw = const {},
  });

  factory NodePingResponse.fromJson(Map<String, dynamic> json) {
    return NodePingResponse(
      status: (json['status'] as String?) ?? '',
      service: (json['service'] as String?) ?? '',
      version: (json['version'] as String?) ?? '',
      deviceName: (json['deviceName'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? '',
      port: (json['port'] as int?) ?? LocalSyncServer.kDefaultPort,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'service': service,
        'version': version,
        'deviceName': deviceName,
        'platform': platform,
        'port': port,
        'timestamp': timestamp?.toUtc().toIso8601String(),
      };
}

/// HTTP client for interacting with remote Orpheus desktop sync servers on the LAN.
///
/// Handles:
/// - Node health checks and discovery verification (`pingNode()`)
/// - Library metadata synchronization (`fetchLibrary()`)
/// - URL resolution for streaming, artwork, and full-fidelity downloads
/// - Track binary downloads with optional SHA-256 verification
class LocalSyncClient {
  final String? baseUrl;
  final http.Client _client;
  final bool _shouldCloseClient;
  final Duration timeout;

  LocalSyncClient({
    this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  })  : _client = client ?? http.Client(),
        _shouldCloseClient = client == null;

  /// Creates a client targeting a [DiscoveredNode] found via [OrpheusBeaconService].
  factory LocalSyncClient.fromNode(
    DiscoveredNode node, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return LocalSyncClient(
      baseUrl: node.baseUrl,
      client: client,
      timeout: timeout,
    );
  }

  // ── URL Resolution Helpers ──────────────────────────────────────────────────

  /// Normalizes a base URL string to guarantee no trailing slashes and default `http://`.
  static String normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    return trimmed;
  }

  /// Resolves the effective base URL, preferring [overrideBaseUrl] if provided.
  String _resolveBaseUrl([String? overrideBaseUrl]) {
    final candidate = overrideBaseUrl ?? baseUrl;
    if (candidate == null || candidate.trim().isEmpty) {
      throw LocalSyncClientException(
        'Base URL must be specified in the constructor or passed as an argument.',
      );
    }
    return normalizeBaseUrl(candidate);
  }

  /// Combines a base URL with a relative path. If [pathOrUrl] is already absolute, returns it unchanged.
  static String joinUrl(String base, String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final cleanBase = normalizeBaseUrl(base);
    final cleanPath = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$cleanBase$cleanPath';
  }

  /// Returns the full streaming URL for [trackId].
  String getStreamUrl(String trackId, [String? baseUrl]) =>
      buildStreamUrl(trackId, baseUrl: baseUrl);

  /// Named-argument variant for building streaming URLs.
  String buildStreamUrl(String trackId, {String? baseUrl}) {
    final effectiveBase = _resolveBaseUrl(baseUrl);
    return '$effectiveBase/api/v1/stream/$trackId';
  }

  /// Returns the full cover artwork URL for [trackId].
  String getArtUrl(String trackId, [String? baseUrl]) =>
      buildArtUrl(trackId, baseUrl: baseUrl);

  /// Named-argument variant for building artwork URLs.
  String buildArtUrl(String trackId, {String? baseUrl}) {
    final effectiveBase = _resolveBaseUrl(baseUrl);
    return '$effectiveBase/api/v1/art/$trackId';
  }

  /// Returns the full file download URL for [trackId].
  String getDownloadUrl(String trackId, [String? baseUrl]) =>
      buildDownloadUrl(trackId, baseUrl: baseUrl);

  /// Named-argument variant for building download URLs.
  String buildDownloadUrl(String trackId, {String? baseUrl}) {
    final effectiveBase = _resolveBaseUrl(baseUrl);
    return '$effectiveBase/api/v1/download/$trackId';
  }

  /// Returns the streaming URL as a parsed [Uri].
  Uri getStreamUri(String trackId, [String? baseUrl]) =>
      Uri.parse(getStreamUrl(trackId, baseUrl));

  /// Returns the artwork URL as a parsed [Uri].
  Uri getArtUri(String trackId, [String? baseUrl]) =>
      Uri.parse(getArtUrl(trackId, baseUrl));

  /// Returns the download URL as a parsed [Uri].
  Uri getDownloadUri(String trackId, [String? baseUrl]) =>
      Uri.parse(getDownloadUrl(trackId, baseUrl));

  // ── Network Operations ──────────────────────────────────────────────────────

  /// Pings the remote Orpheus node at [nodeBaseUrl] or [baseUrl].
  ///
  /// Returns a [NodePingResponse] containing device identity, platform, and server health.
  Future<NodePingResponse> pingNode([String? nodeBaseUrl]) async {
    final effectiveBase = _resolveBaseUrl(nodeBaseUrl);
    final uri = Uri.parse('$effectiveBase/api/v1/ping');

    try {
      final response = await _client.get(uri).timeout(timeout);

      if (response.statusCode != 200) {
        throw LocalSyncClientException(
          'Node ping failed with HTTP status ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw LocalSyncClientException('Malformed ping JSON response: expected Map');
      }

      return NodePingResponse.fromJson(decoded);
    } on LocalSyncClientException {
      rethrow;
    } on TimeoutException catch (e) {
      throw LocalSyncClientException('Node ping timed out after ${timeout.inSeconds}s', cause: e);
    } catch (e) {
      throw LocalSyncClientException('Node ping network error: $e', cause: e);
    }
  }

  /// Fetches the remote library catalog from [nodeBaseUrl] or [baseUrl].
  ///
  /// Converts the remote tracks into [Track] instances configured for immediate
  /// streaming playback via [AudioPlayerService], with [Track.filePath] set to the
  /// full streaming URL and [Track.customMetadata.customCoverPath] set to the remote art URL.
  Future<List<Track>> fetchLibrary([String? nodeBaseUrl]) async {
    final effectiveBase = _resolveBaseUrl(nodeBaseUrl);
    final uri = Uri.parse('$effectiveBase/api/v1/library');

    try {
      final response = await _client.get(uri).timeout(timeout);

      if (response.statusCode != 200) {
        throw LocalSyncClientException(
          'Failed to fetch library with HTTP status ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw LocalSyncClientException('Malformed library response: expected Map');
      }

      if (decoded['status'] != 'ok') {
        throw LocalSyncClientException(
          'Server returned non-ok status: ${decoded['status']}',
        );
      }

      final tracksList = decoded['tracks'];
      if (tracksList is! List) {
        throw LocalSyncClientException('Malformed library response: tracks is not a list');
      }

      final List<Track> tracks = [];
      for (final rawItem in tracksList) {
        if (rawItem is! Map<String, dynamic>) continue;
        final track = _mapRemoteItemToTrack(rawItem, effectiveBase);
        tracks.add(track);
      }

      DebugLogger.log(
        'LocalSyncClient: Successfully fetched ${tracks.length} tracks from $effectiveBase',
      );
      return tracks;
    } on LocalSyncClientException {
      rethrow;
    } on TimeoutException catch (e) {
      throw LocalSyncClientException('Library fetch timed out after ${timeout.inSeconds}s', cause: e);
    } catch (e) {
      throw LocalSyncClientException('Failed to retrieve remote library: $e', cause: e);
    }
  }

  /// Downloads the complete media file for [trackId].
  ///
  /// If the server supplies an `X-Orpheus-SHA256` header, the file's hash
  /// is checked to guarantee bit-for-bit integrity.
  Future<List<int>> downloadTrack(
    String trackId, {
    String? baseUrl,
    bool verifyChecksum = true,
  }) async {
    final downloadUrl = getDownloadUrl(trackId, baseUrl);
    final uri = Uri.parse(downloadUrl);

    try {
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        throw LocalSyncClientException(
          'Failed to download track $trackId',
          statusCode: response.statusCode,
        );
      }

      final bytes = response.bodyBytes;

      if (verifyChecksum) {
        final expectedSha = response.headers['x-orpheus-sha256'] ??
            response.headers['X-Orpheus-SHA256'];
        if (expectedSha != null && expectedSha.trim().isNotEmpty) {
          final actualSha = sha256.convert(bytes).toString();
          if (actualSha.toLowerCase() != expectedSha.trim().toLowerCase()) {
            throw LocalSyncClientException(
              'SHA-256 integrity verification failed for track $trackId: expected $expectedSha, got $actualSha',
            );
          }
        }
      }

      return bytes;
    } on LocalSyncClientException {
      rethrow;
    } catch (e) {
      throw LocalSyncClientException('Download failed for track $trackId: $e', cause: e);
    }
  }

  /// Maps an individual item from the `/api/v1/library` response into an Orpheus [Track].
  Track _mapRemoteItemToTrack(Map<String, dynamic> item, String effectiveBase) {
    final trackId = (item['trackId'] as String?) ?? '';
    final streamPath = (item['streamUrl'] as String?) ?? '/api/v1/stream/$trackId';
    final streamUrl = joinUrl(effectiveBase, streamPath);

    final track = Track()
      ..trackId = trackId
      ..filePath = streamUrl
      ..title = item['title'] as String?
      ..artist = item['artist'] as String?
      ..album = item['album'] as String?
      ..duration = (item['duration'] as num?)?.toInt() ?? 0
      ..fileType = _parseFileType(item['fileType'])
      ..audioQuality = (item['audioQuality'] as String?) ?? 'STREAM'
      ..isLiked = item['isLiked'] == true;

    final hasCover = item['hasCover'] == true;
    final artPath = item['artUrl'] as String?;
    if (hasCover && artPath != null && artPath.isNotEmpty) {
      final fullArtUrl = joinUrl(effectiveBase, artPath);
      track.hasCustomMetadata = true;
      track.customMetadata = CustomMetadata()..customCoverPath = fullArtUrl;
    } else {
      track.hasCustomMetadata = false;
      track.customMetadata = CustomMetadata();
    }

    final downloadPath = item['downloadUrl'] as String?;
    if (downloadPath != null && downloadPath.isNotEmpty) {
      track.downloadSource = joinUrl(effectiveBase, downloadPath);
    }

    return track;
  }

  /// Converts a file type string into the corresponding [FileType] enum.
  FileType _parseFileType(dynamic val) {
    if (val is! String) return FileType.unknown;
    final clean = val.toLowerCase().trim();
    for (final type in FileType.values) {
      if (type.name.toLowerCase() == clean) return type;
    }
    return FileType.unknown;
  }

  /// Closes the internal HTTP client if this instance owns it.
  void close() {
    if (_shouldCloseClient) {
      _client.close();
    }
  }

  /// Alias for [close].
  void dispose() => close();
}
