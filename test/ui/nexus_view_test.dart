import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orpheus/core/models/models.dart';
import 'package:orpheus/core/network/local_sync_client.dart';
import 'package:orpheus/core/network/orpheus_beacon_service.dart';
import 'package:orpheus/core/services/sync_download_manager.dart';
import 'package:orpheus/ui/views/nexus_view.dart';

// ---------------------------------------------------------------------------
// Helper: Advances the Flutter clock enough for async I/O and a single
// animation frame to complete, WITHOUT blocking on infinite repeat animations.
// ---------------------------------------------------------------------------
Future<void> _settle(WidgetTester tester) async {
  // Pump microtasks (completes Futures, streams, timers < 1 frame)
  await tester.pump();
  // Advance by 500 ms — enough for HTTP mock + setState + first animation tick
  await tester.pump(const Duration(milliseconds: 500));
  // One more frame for layout and paint
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OrpheusBeaconService beaconService;
  late SyncDownloadManager downloadManager;
  late DiscoveredNode testNode;

  final sampleTracksJson = {
    'status': 'ok',
    'service': 'orpheus-sync',
    'node': 'MacBook-Air-de-Bertha',
    'total': 3,
    'tracks': [
      {
        'trackId': 't1',
        'title': 'Remote Song One',
        'artist': 'Artist Alpha',
        'album': 'Album One',
        'duration': 180,
        'fileType': 'flac',
        'audioQuality': 'LOSSLESS',
        'hasCover': false,
        'streamUrl': '/api/v1/stream/t1',
        'downloadUrl': '/api/v1/download/t1',
      },
      {
        'trackId': 't2-downloaded',
        'title': 'Downloaded Local Song',
        'artist': 'Artist Alpha',
        'album': 'Album One',
        'duration': 210,
        'fileType': 'mp3',
        'audioQuality': 'HQ',
        'hasCover': false,
        'streamUrl': '/api/v1/stream/t2-downloaded',
        'downloadUrl': '/api/v1/download/t2-downloaded',
      },
      {
        'trackId': 't3-video',
        'title': 'Music Video Clip',
        'artist': 'Video Star',
        'album': 'Vídeos',
        'duration': 240,
        'fileType': 'mp4',
        'audioQuality': 'VIDEO',
        'hasCover': false,
        'streamUrl': '/api/v1/stream/t3-video',
        'downloadUrl': '/api/v1/download/t3-video',
      },
    ],
  };

  setUp(() {
    beaconService = OrpheusBeaconService(
      deviceId: 'local-test-device',
      deviceName: 'My-MacBook',
      platform: 'macos',
      serverPort: 50505,
    );

    testNode = DiscoveredNode(
      deviceId: 'bertha-mac-id',
      deviceName: 'MacBook-Air-de-Bertha',
      platform: 'macos',
      port: 50505,
      address: InternetAddress('192.168.1.55'),
      version: '1.0.0',
      lastSeen: DateTime.now(),
    );

    downloadManager = SyncDownloadManager(
      customDownloadDirectory: Directory.systemTemp,
    );
    downloadManager.clearTasksForTesting();
  });

  tearDown(() {
    beaconService.stopListening();
  });

  LocalSyncClient createMockClient(Map<String, dynamic> responseJson) {
    final mockHttp = MockClient((request) async {
      if (request.url.path.contains('/api/v1/library')) {
        return http.Response(
          jsonEncode(responseJson),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{"status":"ok"}', 200);
    });

    return LocalSyncClient(
      baseUrl: 'http://192.168.1.55:50505',
      client: mockHttp,
    );
  }

  group('NexusView (Modo Nexus) UI Tests', () {
    testWidgets('Renders radar search state when no peer nodes exist',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NexusView(
            beaconService: beaconService,
            downloadManager: downloadManager,
          ),
        ),
      );
      // Use _settle instead of pumpAndSettle — avoids timeout from infinite
      // repeat AnimationControllers (_pulseCtrl, _SkeletonTile._ctrl).
      await _settle(tester);

      expect(find.text('MODO NEXUS'), findsOneWidget);
      expect(find.text('RED LOCAL'), findsOneWidget);
      expect(find.text('No se detectaron dispositivos en red'), findsOneWidget);
      expect(find.text('Escanear Red Local'), findsOneWidget);
    });

    testWidgets('Displays node selector pill and auto-selects first discovered node',
        (tester) async {
      beaconService.addOrUpdateNode(testNode);

      final client = createMockClient(sampleTracksJson);

      await tester.pumpWidget(
        MaterialApp(
          home: NexusView(
            beaconService: beaconService,
            syncClient: client,
            downloadManager: downloadManager,
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('MODO NEXUS'), findsOneWidget);
      expect(find.text('MacBook-Air-de-Bertha'), findsOneWidget);
      expect(find.text('Canciones'), findsOneWidget);
      expect(find.text('Álbumes'), findsOneWidget);
      expect(find.text('Artistas'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
    });

    testWidgets('Populates catalog tracks with dynamic download vs streaming states',
        (tester) async {
      beaconService.addOrUpdateNode(testNode);

      // Register t2-downloaded as completed in download manager
      final downloadedTrack = Track()
        ..trackId = 't2-downloaded'
        ..filePath = '/local/path/t2.mp3'
        ..title = 'Downloaded Local Song';

      downloadManager.registerTaskForTesting(
        SyncDownloadTask(
          trackId: 't2-downloaded',
          track: downloadedTrack,
          client: LocalSyncClient(baseUrl: 'http://192.168.1.55:50505'),
          status: SyncDownloadStatus.completed,
        ),
      );

      final client = createMockClient(sampleTracksJson);

      await tester.pumpWidget(
        MaterialApp(
          home: NexusView(
            beaconService: beaconService,
            syncClient: client,
            downloadManager: downloadManager,
          ),
        ),
      );
      await _settle(tester);

      // Check all 3 tracks are shown
      expect(find.text('Remote Song One'), findsOneWidget);
      expect(find.text('Downloaded Local Song'), findsOneWidget);
      expect(find.text('Music Video Clip'), findsOneWidget);

      // t2-downloaded should show green checkmark
      expect(find.byTooltip('Descargado localmente'), findsOneWidget);

      // Remote tracks should show streaming icon and download button
      expect(find.byTooltip('Disponible vía streaming local'), findsNWidgets(2));
      expect(find.byTooltip('Descargar canción'), findsNWidgets(2));
    });

    testWidgets('Real-time search bar filters tracks dynamically',
        (tester) async {
      beaconService.addOrUpdateNode(testNode);
      final client = createMockClient(sampleTracksJson);

      await tester.pumpWidget(
        MaterialApp(
          home: NexusView(
            beaconService: beaconService,
            syncClient: client,
            downloadManager: downloadManager,
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Remote Song One'), findsOneWidget);
      expect(find.text('Downloaded Local Song'), findsOneWidget);

      // Enter query in search bar
      final searchInput = find.byType(TextField);
      expect(searchInput, findsOneWidget);

      await tester.enterText(searchInput, 'Downloaded');
      await _settle(tester);

      expect(find.text('Downloaded Local Song'), findsOneWidget);
      expect(find.text('Remote Song One'), findsNothing);
    });

    testWidgets('Subtab switching displays Álbumes, Artistas, and Videos',
        (tester) async {
      beaconService.addOrUpdateNode(testNode);
      final client = createMockClient(sampleTracksJson);

      await tester.pumpWidget(
        MaterialApp(
          home: NexusView(
            beaconService: beaconService,
            syncClient: client,
            downloadManager: downloadManager,
          ),
        ),
      );
      await _settle(tester);

      // Tap Álbumes subtab
      await tester.tap(find.text('Álbumes'));
      await _settle(tester);

      expect(find.text('Album One'), findsOneWidget);

      // Tap Artistas subtab
      await tester.tap(find.text('Artistas'));
      await _settle(tester);

      expect(find.text('Artist Alpha'), findsOneWidget);

      // Tap Videos subtab
      await tester.tap(find.text('Videos'));
      await _settle(tester);

      expect(find.text('Music Video Clip'), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);
    });

    testWidgets('Shows disconnect banner when node drops offline',
        (tester) async {
      beaconService.addOrUpdateNode(testNode);
      final client = createMockClient(sampleTracksJson);

      await tester.pumpWidget(
        MaterialApp(
          home: NexusView(
            beaconService: beaconService,
            syncClient: client,
            downloadManager: downloadManager,
          ),
        ),
      );
      await _settle(tester);

      expect(find.textContaining('Nodo desconectado'), findsNothing);

      // Node drops offline: beacon removes it
      beaconService.removeNode(testNode.deviceId);
      await _settle(tester);

      // Disconnect banner is now visible
      expect(find.textContaining('Nodo desconectado'), findsOneWidget);
      expect(find.text('Reconectar'), findsOneWidget);
      // Catalog content is retained (graceful degradation)
      expect(find.text('Remote Song One'), findsOneWidget);
    });
  });
}
