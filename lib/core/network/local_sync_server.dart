import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../database/local_database.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../utils/debug_logger.dart';

/// Lightweight embedded HTTP server providing local network synchronization
/// and real-time audio streaming for Orpheus.
///
/// Features:
/// - Node discovery ping (`/api/v1/ping`)
/// - Library metadata catalog (`/api/v1/library`)
/// - HTTP Range-based audio streaming with 64 KB chunks (`/api/v1/stream/<trackId>`)
/// - Cover artwork distribution (`/api/v1/art/<trackId>`)
/// - Bit-for-bit file download with SHA-256 verification (`/api/v1/download/<trackId>`)
class LocalSyncServer {
  final LocalDatabase? db;
  final Future<List<Track>> Function()? tracksProvider;
  final Future<Track?> Function(String trackId)? trackByIdProvider;
  final Future<List<Playlist>> Function()? playlistsProvider;
  final String? _customDeviceName;

  /// Default port for the Orpheus sync server.
  static const int kDefaultPort = 50505;

  /// Chunk size for RandomAccessFile streaming (64 KB).
  static const int kStreamingChunkSize = 64 * 1024;

  HttpServer? _server;
  int? _actualPort;

  // In-memory cache for SHA-256 checksums to prevent repeated heavy hashing on downloads.
  final Map<String, String> _sha256Cache = {};

  LocalSyncServer({
    this.db,
    this.tracksProvider,
    this.trackByIdProvider,
    this.playlistsProvider,
    String? deviceName,
  }) : _customDeviceName = deviceName;

  /// Global singleton instance.
  static final LocalSyncServer instance = LocalSyncServer();

  /// Whether the HTTP server is currently listening.
  bool get isRunning => _server != null;

  /// Currently bound port or default if inactive.
  int get port => _actualPort ?? _server?.port ?? kDefaultPort;

  /// Human-readable device name exposed to LAN peers.
  String get deviceName {
    final custom = _customDeviceName;
    if (custom != null && custom.trim().isNotEmpty) {
      return custom;
    }
    return Platform.localHostname;
  }

  /// Protocol version.
  String get version => '1.0.0';

  /// Reactive notifier for server running state changes.
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  /// Returns non-loopback IPv4 addresses assigned to active network interfaces.
  static Future<List<String>> getLocalIpAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final ips = <String>[];
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.isNotEmpty) {
            ips.add(addr.address);
          }
        }
      }
      return ips;
    } catch (_) {
      return [];
    }
  }

  /// Starts the HTTP server on [port]. If port is 0, an ephemeral port is assigned.
  /// Binds by default to `InternetAddress.anyIPv4` (0.0.0.0) to accept incoming connections
  /// from any device on the local network.
  Future<void> start({
    int port = kDefaultPort,
    dynamic bindAddress,
    bool shared = true,
  }) async {
    if (_server != null) return;

    try {
      final pipeline = const Pipeline()
          .addMiddleware(_corsMiddleware())
          .addHandler(router.call);

      InternetAddress resolvedAddress;
      if (bindAddress == null) {
        resolvedAddress = InternetAddress.anyIPv4;
      } else if (bindAddress is InternetAddress) {
        resolvedAddress = bindAddress;
      } else if (bindAddress is String) {
        resolvedAddress = InternetAddress(bindAddress);
      } else {
        resolvedAddress = InternetAddress.anyIPv4;
      }

      _server = await shelf_io.serve(
        pipeline,
        resolvedAddress,
        port,
        shared: shared,
      );

      _actualPort = _server!.port;
      isRunningNotifier.value = true;

      final localIps = await getLocalIpAddresses();
      final reachableUrls = localIps.isNotEmpty
          ? localIps.map((ip) => 'http://$ip:$_actualPort').join(', ')
          : 'http://${resolvedAddress.address}:$_actualPort';

      DebugLogger.log(
        'LocalSyncServer: Listening on $reachableUrls ($deviceName)',
      );
    } catch (e, stack) {
      DebugLogger.log('LocalSyncServer: Failed to start on port $port: $e\n$stack');
      rethrow;
    }
  }

  /// Stops the HTTP server and releases bound sockets.
  Future<void> stop() async {
    if (_server != null) {
      final oldPort = _actualPort;
      await _server!.close(force: true);
      _server = null;
      _actualPort = null;
      _sha256Cache.clear();
      isRunningNotifier.value = false;
      DebugLogger.log('LocalSyncServer: Stopped on port $oldPort');
    }
  }

  /// Exposes the shelf [Handler] directly (useful for hermetic unit testing without sockets).
  Handler get handler => const Pipeline()
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  /// Configures and returns the shelf [Router] with all `/api/v1/` endpoints.
  Router get router {
    final app = Router();

    app.get('/api/v1/ping', _handlePing);
    app.get('/api/v1/library', _handleLibrary);
    app.get('/api/v1/stream/<trackId>', _handleStream);
    app.get('/api/v1/art/<trackId>', _handleArt);
    app.get('/api/v1/download/<trackId>', _handleDownload);

    return app;
  }

  // ── Route Handlers ────────────────────────────────────────────────────────

  /// `GET /api/v1/ping`
  /// Returns node health, platform, version, and device name.
  Response _handlePing(Request request) {
    final payload = {
      'status': 'ok',
      'service': 'orpheus-sync',
      'version': version,
      'deviceName': deviceName,
      'platform': Platform.operatingSystem,
      'port': port,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    return Response.ok(
      jsonEncode(payload),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// `GET /api/v1/library`
  /// Returns all indexed tracks with structured metadata and resource endpoints.
  Future<Response> _handleLibrary(Request request) async {
    try {
      final tracks = await _getAllTracks();
      final trackIdMap = <int, String>{};
      for (final t in tracks) {
        trackIdMap[t.id] = t.trackId;
      }

      final items = tracks.map((t) {
        final hasCover = t.customMetadata.customCoverPath != null &&
            t.customMetadata.customCoverPath!.trim().isNotEmpty;
        return {
          'trackId': t.trackId,
          'title': t.displayTitle,
          'artist': t.displayArtist,
          'album': t.displayAlbum,
          'duration': t.duration,
          'fileType': t.fileType.name,
          'audioQuality': t.audioQuality,
          'hasCover': hasCover,
          'isLiked': t.isLiked,
          'streamUrl': '/api/v1/stream/${t.trackId}',
          'artUrl': hasCover ? '/api/v1/art/${t.trackId}' : null,
          'downloadUrl': '/api/v1/download/${t.trackId}',
        };
      }).toList();

      final playlists = await _getAllPlaylists();
      final playlistItems = playlists.map((p) {
        final trackUuids = p.trackIds
            .map((id) => trackIdMap[id])
            .whereType<String>()
            .toList();
        return {
          'playlistId': p.playlistId,
          'name': p.name,
          'description': p.description,
          'isDefault': p.isDefault,
          'trackCount': trackUuids.length,
          'trackIds': trackUuids,
          'updatedAt': p.updatedAt?.toUtc().toIso8601String(),
        };
      }).toList();

      final payload = {
        'status': 'ok',
        'count': items.length,
        'tracks': items,
        'playlists': playlistItems,
      };

      return Response.ok(
        jsonEncode(payload),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e, stack) {
      DebugLogger.log('LocalSyncServer: Error fetching library: $e\n$stack');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to retrieve library: $e'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// `GET /api/v1/stream/<trackId>`
  /// Audio streaming with full HTTP 206 Partial Content support for Seek.
  Future<Response> _handleStream(Request request, String trackId) async {
    final track = await _getTrackById(trackId);
    if (track == null) {
      return Response.notFound(
        jsonEncode({'error': 'Track not found: $trackId'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final file = File(track.filePath);
    if (!await file.exists()) {
      return Response.notFound(
        jsonEncode({'error': 'Audio file does not exist on disk'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final fileLength = await file.length();
    final mimeType = _mimeTypeForAudio(track.filePath, track.fileType);
    final rangeHeader = request.headers['range'] ?? request.headers['Range'];

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      return _serveByteRange(file, fileLength, mimeType, rangeHeader);
    }

    // Full playback (HTTP 200) when client requests no range
    final raf = await file.open(mode: FileMode.read);
    return Response.ok(
      _streamByteRange(raf, fileLength),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': fileLength.toString(),
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      },
    );
  }

  /// Serves an HTTP 206 Partial Content slice using RandomAccessFile seeking.
  Future<Response> _serveByteRange(
    File file,
    int fileLength,
    String mimeType,
    String rangeHeader,
  ) async {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(rangeHeader.trim());
    if (match == null) {
      return Response(
        416,
        body: jsonEncode({'error': 'Invalid Range syntax'}),
        headers: {
          'Content-Range': 'bytes */$fileLength',
          'Accept-Ranges': 'bytes',
          'Content-Type': 'application/json; charset=utf-8',
        },
      );
    }

    final startStr = match.group(1);
    final endStr = match.group(2);

    int start = 0;
    int end = fileLength - 1;

    if (startStr != null && startStr.isNotEmpty && (endStr == null || endStr.isEmpty)) {
      // bytes=1024-
      start = int.tryParse(startStr) ?? 0;
    } else if ((startStr == null || startStr.isEmpty) && endStr != null && endStr.isNotEmpty) {
      // bytes=-500 (suffix bytes)
      final suffix = int.tryParse(endStr) ?? 0;
      start = (fileLength - suffix).clamp(0, fileLength - 1);
    } else if (startStr != null && startStr.isNotEmpty && endStr != null && endStr.isNotEmpty) {
      // bytes=1024-2048
      start = int.tryParse(startStr) ?? 0;
      end = int.tryParse(endStr) ?? (fileLength - 1);
    }

    if (fileLength == 0 || start > end || start >= fileLength || start < 0) {
      return Response(
        416,
        body: jsonEncode({'error': 'Requested Range Not Satisfiable'}),
        headers: {
          'Content-Range': 'bytes */$fileLength',
          'Accept-Ranges': 'bytes',
          'Content-Type': 'application/json; charset=utf-8',
        },
      );
    }

    end = end.clamp(0, fileLength - 1);
    final contentLength = end - start + 1;

    final raf = await file.open(mode: FileMode.read);
    await raf.setPosition(start);

    return Response(
      206,
      body: _streamByteRange(raf, contentLength),
      headers: {
        'Content-Range': 'bytes $start-$end/$fileLength',
        'Accept-Ranges': 'bytes',
        'Content-Length': contentLength.toString(),
        'Content-Type': mimeType,
        'Cache-Control': 'no-cache',
      },
    );
  }

  /// Streams up to [length] bytes in chunks of [chunkSize] (default 64 KB).
  /// Closes the [raf] handle reliably on completion or early cancellation.
  Stream<List<int>> _streamByteRange(
    RandomAccessFile raf,
    int length, {
    int chunkSize = kStreamingChunkSize,
  }) async* {
    try {
      int remaining = length;
      while (remaining > 0) {
        final toRead = remaining > chunkSize ? chunkSize : remaining;
        final buffer = await raf.read(toRead);
        if (buffer.isEmpty) break;
        yield buffer;
        remaining -= buffer.length;
      }
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
  }

  /// `GET /api/v1/art/<trackId>`
  /// Returns the cover art image binary for the specified track.
  Future<Response> _handleArt(Request request, String trackId) async {
    final track = await _getTrackById(trackId);
    if (track == null) {
      return Response.notFound(
        jsonEncode({'error': 'Track not found: $trackId'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final coverPath = track.customMetadata.customCoverPath;
    if (coverPath == null || coverPath.trim().isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'No custom cover art found for track: $trackId'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final file = File(coverPath);
    if (!await file.exists()) {
      return Response.notFound(
        jsonEncode({'error': 'Cover art file does not exist on disk'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final length = await file.length();
    final mimeType = _mimeTypeForImage(coverPath);

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': length.toString(),
        'Cache-Control': 'public, max-age=86400',
      },
    );
  }

  /// `GET /api/v1/download/<trackId>`
  /// Transmits the raw original file with 'X-Orpheus-SHA256' verification header.
  Future<Response> _handleDownload(Request request, String trackId) async {
    final track = await _getTrackById(trackId);
    if (track == null) {
      return Response.notFound(
        jsonEncode({'error': 'Track not found: $trackId'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final file = File(track.filePath);
    if (!await file.exists()) {
      return Response.notFound(
        jsonEncode({'error': 'File not found on disk: ${track.filePath}'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final length = await file.length();
    final checksum = await _calculateFileSha256(file, trackId);
    final rawFileName = p.basename(track.filePath);
    final mimeType = _mimeTypeForAudio(track.filePath, track.fileType);

    // RFC 6266 / RFC 5987: Avoid FormatException in dart:io when track filenames contain
    // non-ASCII characters (tildes, eñes, NFD decomposed Unicode from macOS, etc.).
    final asciiFallback = rawFileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    final rfc5987Encoded = Uri.encodeComponent(rawFileName);

    final headers = <String, String>{
      'Content-Type': mimeType,
      'Content-Length': length.toString(),
      'Content-Disposition':
          'attachment; filename="$asciiFallback"; filename*=UTF-8\'\'$rfc5987Encoded',
      'Cache-Control': 'no-cache',
    };
    if (checksum.isNotEmpty) {
      headers['X-Orpheus-SHA256'] = checksum;
    }

    return Response.ok(
      file.openRead(),
      headers: headers,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<List<Track>> _getAllTracks() async {
    final provider = tracksProvider;
    if (provider != null) {
      return provider();
    }
    final database = db ?? LocalDatabase.instance;
    return database.getAllTracks();
  }

  Future<List<Playlist>> _getAllPlaylists() async {
    final provider = playlistsProvider;
    if (provider != null) {
      return provider();
    }
    final database = db ?? LocalDatabase.instance;
    return database.getAllPlaylists();
  }

  Future<Track?> _getTrackById(String trackId) async {
    final provider = trackByIdProvider;
    if (provider != null) {
      return provider(trackId);
    }
    final database = db ?? LocalDatabase.instance;
    return database.getTrackByTrackId(trackId);
  }

  Future<String> _calculateFileSha256(File file, String trackId) async {
    try {
      final stat = await file.stat();
      final cacheKey = '$trackId:${stat.modified.millisecondsSinceEpoch}:${stat.size}';
      if (_sha256Cache.containsKey(cacheKey)) {
        return _sha256Cache[cacheKey]!;
      }

      // If the file is large (> 25 MB), schedule background hashing and do not block headers.
      if (stat.size > 25 * 1024 * 1024) {
        unawaited(
          sha256.bind(file.openRead()).first.then((d) {
            _sha256Cache[cacheKey] = d.toString();
          }).catchError((_) {}),
        );
        return '';
      }

      // For files <= 25 MB, compute with a strict timeout to ensure initial headers dispatch immediately.
      try {
        final digest = await sha256.bind(file.openRead()).first.timeout(
          const Duration(milliseconds: 500),
        );
        final hex = digest.toString();
        _sha256Cache[cacheKey] = hex;
        return hex;
      } on TimeoutException {
        // If taking longer than 500ms, compute in background for subsequent requests and return empty to not block
        unawaited(
          sha256.bind(file.openRead()).first.then((d) {
            _sha256Cache[cacheKey] = d.toString();
          }).catchError((_) {}),
        );
        return '';
      }
    } catch (e) {
      // Fallback: Return empty and allow immediate streaming
      return '';
    }
  }

  static String _mimeTypeForAudio(String filePath, FileType fileType) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'flac':
        return 'audio/flac';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      default:
        if (fileType == FileType.flac) return 'audio/flac';
        if (fileType == FileType.mp3) return 'audio/mpeg';
        if (fileType == FileType.m4a) return 'audio/mp4';
        if (fileType == FileType.wav) return 'audio/wav';
        if (fileType == FileType.mp4) return 'video/mp4';
        return 'application/octet-stream';
    }
  }

  static String _mimeTypeForImage(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// CORS Middleware enabling web or hybrid peer clients to reach endpoints.
  static Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers':
                'Origin, Content-Type, Range, X-Orpheus-SHA256',
            'Access-Control-Expose-Headers':
                'Content-Range, Accept-Ranges, Content-Length, X-Orpheus-SHA256',
          });
        }
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Expose-Headers':
              'Content-Range, Accept-Ranges, Content-Length, X-Orpheus-SHA256',
        });
      };
    };
  }
}
