import 'dart:async';
import 'dart:io';
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

bool _metadataGodInitialized = false;

/// Runs the resilient startup sequence with parallelized independent services.
Future<void> runOrpheusStartupSequence() async {
  // 1. Independent essential C/FFI engines
  try {
    DebugLogger.log('Iniciando MediaKit.ensureInitialized()...');
    MediaKit.ensureInitialized();
  } catch (e, s) {
    DebugLogger.log('ERROR en MediaKit: $e\n$s');
  }

  if (!_metadataGodInitialized) {
    try {
      await MetadataGod.initialize();
      _metadataGodInitialized = true;
    } catch (e, s) {
      DebugLogger.log('ERROR en MetadataGod: $e\n$s');
    }
  }

  // 2. AudioService and LocalDatabase in parallel to eliminate sequential timeout sum
  await Future.wait([
    // AudioService init
    (() async {
      if (OrpheusAudioHandler.hasInstance) return;
      try {
        DebugLogger.log('Iniciando AudioService.init()...');
        final audioHandler = await AudioService.init(
          builder: () => OrpheusAudioHandler(),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.heyzell.orpheus.channel.playback_v2',
            androidNotificationChannelName: 'Orpheus Reproduccion',
            androidNotificationChannelDescription:
                'Controles de reproduccion de musica de Orpheus',
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
        DebugLogger.log('ERROR en AudioService.init: $e\n$s');
      }
    })(),
    // LocalDatabase init
    (() async {
      DebugLogger.log('Iniciando LocalDatabase.initialize()...');
      await LocalDatabase.instance.initialize();
    })(),
  ]);

  // 3. Post-DB setup: hook reactive database listeners
  if (OrpheusAudioHandler.hasInstance) {
    OrpheusAudioHandler.instance.initAfterDatabaseReady();
  }

  // 4. Asynchronously restore playback state in the background without delaying startup frame
  unawaited(
    AudioPlayerService.instance.hydratePlaybackState().catchError((e, s) {
      DebugLogger.log('ERROR en AudioPlayerService hydration: $e\n$s');
    }),
  );
}

/// Entry point for Orpheus.
void main() {
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
    DebugLogger.log('UNCAUGHT ASYNC ERROR: $error\n$stack');
    return true;
  };

  // Restrict orientation to vertical exclusively on mobile platforms
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  _startApp();
}

Future<void> _startApp() async {
  try {
    await runOrpheusStartupSequence().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
          'El arranque global de Orpheus excedió el tiempo máximo de 15s.'),
    );

    runApp(const OrpheusApp());

    // Background tasks scheduled post-UI mount
    Future.delayed(const Duration(seconds: 2), () {
      PermissionService.requestNotificationPermission();
      AlbumArtFetcherService.instance.processLibrary();
    });
  } catch (error, stack) {
    DebugLogger.log('FALLO CRÍTICO EN ARRANQUE: $error\n$stack');
    runApp(OrpheusRecoveryApp(
      errorMessage: error.toString(),
      stackTrace: stack,
    ));
  }
}

/// Root application widget.
class OrpheusApp extends StatelessWidget {
  const OrpheusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: MaterialApp(
        title: 'Orpheus',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: const MainLayout(),
      ),
    );
  }
}

/// Nivel 2: Interactive Recovery Screen presented when silent auto-repair fails.
/// Prevents black screen deadlocks and bootloops, providing safe restoration options.
class OrpheusRecoveryApp extends StatefulWidget {
  final String errorMessage;
  final StackTrace? stackTrace;

  const OrpheusRecoveryApp({
    super.key,
    required this.errorMessage,
    this.stackTrace,
  });

  @override
  State<OrpheusRecoveryApp> createState() => _OrpheusRecoveryAppState();
}

class _OrpheusRecoveryAppState extends State<OrpheusRecoveryApp> {
  bool _isRecovering = false;
  String? _statusText;

  Future<void> _handleRestoreDatabase() async {
    setState(() {
      _isRecovering = true;
      _statusText = 'Restaurando base de datos y eliminando archivos residuales...';
    });

    try {
      await LocalDatabase.instance.restoreDatabase();
      setState(() {
        _statusText = 'Base de datos restaurada con éxito. Cerrando aplicación para un reinicio limpio del sistema...';
      });

      await Future.delayed(const Duration(milliseconds: 1200));

      if (Platform.isAndroid) {
        SystemNavigator.pop(animated: true);
        Future.delayed(const Duration(milliseconds: 300), () => exit(0));
      } else {
        exit(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecovering = false;
          _statusText = 'Fallo en la restauración: $e';
        });
      }
    }
  }

  Future<void> _handleRetryStartup() async {
    setState(() {
      _isRecovering = true;
      _statusText = 'Reintentando inicio de Orpheus...';
    });

    try {
      await runOrpheusStartupSequence().timeout(const Duration(seconds: 20));
      if (mounted) {
        runApp(const OrpheusApp());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecovering = false;
          _statusText = 'El reintento falló: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recuperación - Orpheus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE50914),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE50914).withAlpha(80)),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFFE50914),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modo de Recuperación',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Orpheus Resilient Guard',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'No se pudo inicializar la base de datos o el motor de audio debido a un bloqueo o corrupción residual.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SelectableText(
                    widget.errorMessage,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFFF8A8A),
                    ),
                  ),
                ),
                if (_statusText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _statusText!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64B5F6),
                    ),
                  ),
                ],
                const Spacer(),
                if (_isRecovering)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFFE50914),
                      ),
                    ),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _handleRestoreDatabase,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text(
                        'Restaurar Base de Datos',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _handleRetryStartup,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text(
                        'Reintentar Inicio',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    super.key,
    required this.title,
    required this.error,
    this.stackTrace,
  });

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
