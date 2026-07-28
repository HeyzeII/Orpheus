import 'dart:async';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';

import 'core/database/local_database.dart';
import 'core/services/album_art_fetcher_service.dart';
import 'core/services/audio_handler.dart';
import 'core/services/audio_player_service.dart';
import 'ui/layouts/main_shell.dart';
import 'ui/theme/app_theme.dart';

/// Entry point for Orpheus.
///
/// Initialization order is strict and intentional:
/// 1. [WidgetsFlutterBinding.ensureInitialized] — required by all platform plugins.
/// 2. [MediaKit.ensureInitialized] — registers the media_kit native audio engine.
/// 3. [AudioService.init] — registers the Android Foreground Service and MediaSession.
/// 4. [MetadataGod.initialize] — loads the Rust FFI bridge for tag reading.
/// 5. [LocalDatabase.instance.initialize] — opens Isar and seeds default data.
/// 6. [AudioPlayerService.instance.hydratePlaybackState] — restores last queue.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Global handler for rendering errors inside widget trees
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: OrpheusErrorScreen(
          title: 'Error de Renderizado (Widget)',
          error: details.exception.toString(),
          stackTrace: details.stack,
        ),
      );
    };

    // Global Flutter error handler
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };

    // Platform-level asynchronous error handler
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      // Return true to indicate the error was handled
      return true;
    };

    // Enable native Android edge-to-edge mode & transparent system bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    // ── Safe Service Initialization Blocks ───────────────────────────────────

    try {
      MediaKit.ensureInitialized();
    } catch (e, s) {
      runApp(OrpheusErrorScreenApp(
        serviceName: 'MediaKit (Motor de Audio)',
        error: e,
        stackTrace: s,
      ));
      return;
    }

    try {
      await AudioService.init(
        builder: () => OrpheusAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.heyzell.orpheus.channel.audio',
          androidNotificationChannelName: 'Orpheus Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e, s) {
      runApp(OrpheusErrorScreenApp(
        serviceName: 'AudioService (Foreground Session)',
        error: e,
        stackTrace: s,
      ));
      return;
    }

    try {
      await MetadataGod.initialize();
    } catch (e, s) {
      runApp(OrpheusErrorScreenApp(
        serviceName: 'MetadataGod (Tag Editor FFI)',
        error: e,
        stackTrace: s,
      ));
      return;
    }

    try {
      await LocalDatabase.instance.initialize();
    } catch (e, s) {
      runApp(OrpheusErrorScreenApp(
        serviceName: 'LocalDatabase (Isar DB)',
        error: e,
        stackTrace: s,
      ));
      return;
    }

    try {
      await AudioPlayerService.instance.hydratePlaybackState();
    } catch (e, s) {
      runApp(OrpheusErrorScreenApp(
        serviceName: 'AudioPlayerService (Playback Engine)',
        error: e,
        stackTrace: s,
      ));
      return;
    }

    // Defer background album art fetching for any missing cover art to 3 seconds
    // after the app mounts its first frame, avoiding SQLite/sqflite lock collisions at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        AlbumArtFetcherService.instance.processLibrary();
      });
    });

    runApp(const OrpheusApp());
  }, (Object error, StackTrace stack) {
    runApp(OrpheusErrorScreenApp(
      serviceName: 'Excepción Global (Zoned)',
      error: error,
      stackTrace: stack,
    ));
  });
}

/// Root application widget.
class OrpheusApp extends StatelessWidget {
  const OrpheusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const MainLayout(),
    );
  }
}

/// App wrapper to display initialization errors nicely.
class OrpheusErrorScreenApp extends StatelessWidget {
  final String serviceName;
  final Object error;
  final StackTrace stackTrace;

  const OrpheusErrorScreenApp({
    super.key,
    required this.serviceName,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Error de Inicio - Orpheus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5252),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: OrpheusErrorScreen(
          title: 'Fallo al inicializar $serviceName',
          error: error.toString(),
          stackTrace: stackTrace,
        ),
      ),
    );
  }
}

/// A premium visual interface representing an unhandled runtime failure.
class OrpheusErrorScreen extends StatelessWidget {
  final String title;
  final String error;
  final StackTrace? stackTrace;

  const OrpheusErrorScreen({
    key,
    required this.title,
    required this.error,
    this.stackTrace,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFF5252),
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF5252),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              width: double.infinity,
              child: SelectableText(
                error,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Stack Trace:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF333333)),
                ),
                width: double.infinity,
                child: SingleChildScrollView(
                  child: SelectableText(
                    stackTrace?.toString() ?? 'No hay stack trace disponible.',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5252),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: 'Servicio: $title\nError: $error\n\nStackTrace:\n$stackTrace',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Detalles de error copiados al portapapeles'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar detalles del error'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
