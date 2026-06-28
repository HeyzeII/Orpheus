import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';

import 'core/database/local_database.dart';
import 'core/services/album_art_fetcher_service.dart';
import 'core/services/audio_player_service.dart';
import 'ui/layouts/main_shell.dart';
import 'ui/theme/app_theme.dart';

/// Entry point for Orpheus.
///
/// Initialization order is important:
/// 1. [WidgetsFlutterBinding.ensureInitialized] — required by platform plugins.
/// 2. [MediaKit.ensureInitialized] — registers media_kit native audio handlers.
/// 3. [MetadataGod.initialize] — loads the Rust FFI bridge for tag reading.
/// 4. [LocalDatabase.instance.initialize] — opens Isar and seeds default data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await MetadataGod.initialize();
  await LocalDatabase.instance.initialize();
  // Restore last playback queue + position before building the widget tree.
  await AudioPlayerService.instance.hydratePlaybackState();

  // Start background album art fetching for any missing cover art
  AlbumArtFetcherService.instance.processLibrary();

  runApp(const OrpheusApp());
}

/// Root application widget.
///
/// Applies the premium [AppTheme] and renders [MainShell] as the root
/// layout for all desktop navigation.
class OrpheusApp extends StatelessWidget {
  const OrpheusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const MainShell(),
    );
  }
}

