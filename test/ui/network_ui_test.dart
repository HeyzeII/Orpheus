import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/models.dart';
import 'package:orpheus/core/network/local_sync_client.dart';
import 'package:orpheus/core/network/orpheus_beacon_service.dart';
import 'package:orpheus/core/services/sync_download_manager.dart';
import 'package:orpheus/features/network/presentation/nearby_devices_view.dart';
import 'package:orpheus/features/network/presentation/sync_progress_panel.dart';
import 'package:orpheus/ui/widgets/network_indicator_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkIndicatorBadge UI Tests', () {
    testWidgets('Renders nothing when track is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NetworkIndicatorBadge(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RED LOCAL'), findsNothing);
      expect(find.byIcon(Icons.lan_rounded), findsNothing);
    });

    testWidgets('Renders nothing when track is local file', (tester) async {
      final localTrack = Track()
        ..filePath = '/home/user/Music/song.flac'
        ..trackId = 'local-1'
        ..title = 'Local Song'
        ..artist = 'Local Artist';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NetworkIndicatorBadge(track: localTrack),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RED LOCAL'), findsNothing);
      expect(find.byIcon(Icons.lan_rounded), findsNothing);
    });

    testWidgets('Renders RED LOCAL chip when track is remote HTTP URI',
        (tester) async {
      final remoteTrack = Track()
        ..filePath = 'http://192.168.1.42:50505/api/v1/stream/abc123'
        ..trackId = 'remote-1'
        ..title = 'Remote Song'
        ..artist = 'Remote Artist';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NetworkIndicatorBadge(track: remoteTrack),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RED LOCAL'), findsOneWidget);
      expect(find.byIcon(Icons.lan_rounded), findsOneWidget);
    });
  });

  group('SyncProgressPanel UI Tests', () {
    testWidgets('Renders empty state when there are no download tasks',
        (tester) async {
      final manager = SyncDownloadManager(
        customDownloadDirectory: Directory.systemTemp,
      );
      manager.clearTasksForTesting();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncProgressPanel(
              manager: manager,
              isEmbedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sincronización Offline'), findsOneWidget);
      expect(find.text('Sin descargas activas'), findsOneWidget);
      expect(find.text('No hay descargas en curso'), findsOneWidget);
      expect(
        find.text(
          'Conecta un nodo en red local para sincronizar álbumes y pistas.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Renders active download tasks and progress details',
        (tester) async {
      final manager = SyncDownloadManager(
        customDownloadDirectory: Directory.systemTemp,
      );
      manager.clearTasksForTesting();

      final track1 = Track()
        ..filePath = 'http://192.168.1.10:50505/api/v1/stream/t1'
        ..trackId = 'task-t1'
        ..title = 'Starlight Symphony'
        ..artist = 'Orpheus Collective';

      final task1 = SyncDownloadTask(
        trackId: 'task-t1',
        track: track1,
        client: LocalSyncClient(baseUrl: 'http://192.168.1.10:50505'),
        status: SyncDownloadStatus.downloading,
        totalBytes: 10485760,
        bytesDownloaded: 5242880,
        progress: 0.5,
        bytesPerSecond: 2097152, // 2.0 MB/s
      );

      manager.registerTaskForTesting(task1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncProgressPanel(
              manager: manager,
              isEmbedded: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Starlight Symphony'), findsOneWidget);
      expect(find.text('Orpheus Collective'), findsOneWidget);
      expect(find.text('2.00 MB/s'), findsOneWidget);
      expect(find.text('• 50% (2.00 MB/s)'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('Tapping cancel button invokes task cancellation',
        (tester) async {
      final manager = SyncDownloadManager(
        customDownloadDirectory: Directory.systemTemp,
      );
      manager.clearTasksForTesting();

      final track = Track()
        ..filePath = 'http://192.168.1.10:50505/api/v1/stream/cancel-me'
        ..trackId = 'cancel-1'
        ..title = 'Cancelling Track'
        ..artist = 'Echo';

      final task = SyncDownloadTask(
        trackId: 'cancel-1',
        track: track,
        client: LocalSyncClient(baseUrl: 'http://192.168.1.10:50505'),
        status: SyncDownloadStatus.downloading,
      );

      manager.registerTaskForTesting(task);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncProgressPanel(
              manager: manager,
              isEmbedded: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final cancelButton = find.byTooltip('Cancelar descarga');
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await tester.pump();

      expect(task.status, SyncDownloadStatus.cancelled);
    });

    testWidgets('Presents modal bottom sheet using showModal()',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => SyncProgressPanel.showModal(ctx),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Sincronización Offline'), findsOneWidget);
    });
  });

  group('NearbyDevicesView UI Tests', () {
    testWidgets('Renders screen headers, local node card, and manual IP input',
        (tester) async {
      final beaconService = OrpheusBeaconService(
        deviceId: 'local-test-device',
        deviceName: 'Test Workstation',
        platform: 'macOS',
        serverPort: 50505,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NearbyDevicesView(
            beaconService: beaconService,
            autoStartScan: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Red Local y Dispositivos'), findsOneWidget);
      expect(find.text('Nodos Detectados'), findsOneWidget);
      expect(find.text('Conexión Directa por IP'), findsOneWidget);
      expect(find.text('Conectar al Nodo'), findsOneWidget);
      expect(find.text('Dirección IP'), findsOneWidget);
      expect(find.text('Puerto'), findsOneWidget);
    });

    testWidgets('Displays discovered peer nodes with device name and actions',
        (tester) async {
      final beaconService = OrpheusBeaconService(
        deviceId: 'local-host-id',
        deviceName: 'Host Player',
        platform: 'linux',
      );

      final peerNode = DiscoveredNode(
        deviceId: 'peer-fedora-1',
        deviceName: 'Fedora Hi-Fi Server',
        platform: 'linux',
        port: 50505,
        address: InternetAddress('192.168.1.120'),
        version: '1.0.0',
        lastSeen: DateTime.now(),
      );

      beaconService.addOrUpdateNode(peerNode);

      await tester.pumpWidget(
        MaterialApp(
          home: NearbyDevicesView(
            beaconService: beaconService,
            autoStartScan: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fedora Hi-Fi Server'), findsOneWidget);
      expect(find.textContaining('192.168.1.120:50505'), findsOneWidget);
      expect(find.text('Explorar Biblioteca'), findsOneWidget);
      expect(find.byTooltip('Probar conexión'), findsOneWidget);
    });

    testWidgets('Scan toggle updates scanning state icon and tooltip',
        (tester) async {
      final beaconService = OrpheusBeaconService(
        deviceId: 'toggle-test-id',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NearbyDevicesView(
            beaconService: beaconService,
            autoStartScan: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toggleScanBtn = find.byTooltip('Iniciar escaneo');
      expect(toggleScanBtn, findsOneWidget);

      await tester.tap(toggleScanBtn);
      await tester.pump();

      expect(find.byTooltip('Detener escaneo'), findsOneWidget);

      beaconService.stopListening();
    });
  });
}
