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
import 'core/services/permission_service.dart';
import 'core/utils/debug_logger.dart';
import 'ui/layouts/main_shell.dart';
import 'ui/theme/app_theme.dart';

/// Entry point for Orpheus.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Global error handlers
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

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      return true;
    };

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

    // ── Linear Canonical Startup Sequence ───────────────────────────────────

    try {
      DebugLogger.log('Iniciando MediaKit.ensureInitialized()...');
      MediaKit.ensureInitialized();
    } catch (e, s) {
      DebugLogger.log('ERROR en MediaKit: $e\n$s');
    }

    try {
      DebugLogger.log('Solicitando permisos de notificación en arranque...');
      await PermissionService.requestNotificationPermission();
    } catch (e, s) {
      DebugLogger.log('Advertencia permisos notificación: $e\n$s');
    }

    try {
      DebugLogger.log('Iniciando AudioService.init()...');
      // Capture the return value so the native bridge confirms the handler is registered.
      final audioHandler = await AudioService.init(
        builder: () => OrpheusAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.heyzell.orpheus.channel.playback_v2',
          androidNotificationChannelName: 'Orpheus Reproduccion',
          androidNotificationChannelDescription:
              'Controles de reproduccion de musica de Orpheus',
          // Con androidNotificationOngoing: true y androidStopForegroundOnPause: true,
          // la notificacion es fija e inmune a swipe durante la reproduccion en primer plano,
          // y se puede pausar/descartar limpiamente sin romper la asercion.
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidShowNotificationBadge: true,
          androidNotificationClickStartsActivity: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
          preloadArtwork: true,
        ),
      );
      DebugLogger.log('AudioService.init() completado — handler: ${audioHandler.runtimeType}');
    } catch (e, s) {
      DebugLogger.log('ERROR CRÍTICO en AudioService.init: $e\n$s');
    }


    try {
      await MetadataGod.initialize();
    } catch (e, s) {
      DebugLogger.log('ERROR en MetadataGod: $e\n$s');
    }

    try {
      DebugLogger.log('Iniciando LocalDatabase.initialize()...');
      await LocalDatabase.instance.initialize();
    } catch (e, s) {
      DebugLogger.log('ERROR en LocalDatabase: $e\n$s');
    }

    try {
      DebugLogger.log('Hydratando estado de AudioPlayerService...');
      await AudioPlayerService.instance.hydratePlaybackState();
    } catch (e, s) {
      DebugLogger.log('ERROR en AudioPlayerService hydration: $e\n$s');
    }

    if (OrpheusAudioHandler.hasInstance) {
      OrpheusAudioHandler.instance.initAfterDatabaseReady();
    }

    runApp(const OrpheusApp());

    Future.delayed(const Duration(seconds: 3), () {
      AlbumArtFetcherService.instance.processLibrary();
    });
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
                const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5252), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                error,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFFFF8A8A),
                ),
              ),
            ),
            if (stackTrace != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Stack Trace:',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      stackTrace.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
