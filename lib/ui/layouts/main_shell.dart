import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../views/home_view.dart';
import '../views/library_view.dart';
import '../views/lyrics_view.dart';
import '../views/settings_view.dart';
import '../widgets/player_bar.dart';
import '../widgets/sidebar.dart';


/// Root layout shell for Orpheus desktop.
///
/// Composes three fixed regions:
/// - [Sidebar] on the left (fixed 240px, drives navigation state).
/// - Dynamic main content area in the center.
/// - [PlayerBar] at the bottom (fixed 90px, full width).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  NavDestination _selected = NavDestination.home;
  bool _showLyrics = false;

  void _toggleLyrics() => setState(() => _showLyrics = !_showLyrics);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called by Flutter when the app lifecycle changes.
  ///
  /// On [AppLifecycleState.inactive] or [AppLifecycleState.paused] we fire
  /// an immediate state snapshot so that the position is captured even if
  /// the OS suspends the process milliseconds later (e.g. Command+Q on macOS,
  /// home button on Android, or screen lock).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      AudioPlayerService.instance.savePlaybackStateNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Column(
        children: [
          // ── Top row: Sidebar + Main content ──────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar (hidden behind lyrics panel but always built)
                Sidebar(
                  selected: _selected,
                  onSelect: (dest) {
                    setState(() {
                      _selected = dest;
                      _showLyrics = false; // close lyrics on nav change
                    });
                  },
                ),
                // Thin divider between sidebar and content
                Container(width: 1, color: AppTheme.divider),
                // Main content + Lyrics overlay
                Expanded(
                  child: Stack(
                    children: [
                      _ContentArea(destination: _selected),
                      // Lyrics slide-up panel
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOutCubic,
                        offset: _showLyrics
                            ? Offset.zero
                            : const Offset(0, 1),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: _showLyrics ? 1.0 : 0.0,
                          child: StreamBuilder<Track?>(
                            stream: AudioPlayerService
                                .instance.currentTrackStream,
                            initialData: AudioPlayerService
                                .instance.currentTrack,
                            builder: (context, snap) {
                              final track = snap.data;
                              if (track == null) {
                                return const _NoTrackLyricsPlaceholder();
                              }
                              return LyricsView(track: track);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Bottom: Player bar ────────────────────────────────────────────
          PlayerBar(
            lyricsActive: _showLyrics,
            onToggleLyrics: _toggleLyrics,
          ),
        ],
      ),
    );
  }
}

/// Switches the center pane based on active [NavDestination].
///
/// Uses an [IndexedStack] so each view retains its scroll position when
/// the user navigates away and back.
class _ContentArea extends StatelessWidget {
  const _ContentArea({required this.destination});

  final NavDestination destination;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: destination.index,
      children: const [
        HomeView(),
        _PlaceholderView(label: 'Explorar'),
        LibraryView(),
        SettingsView(),
      ],
    );
  }
}

/// Fallback view shown for destinations that are not yet implemented.
class _PlaceholderView extends StatelessWidget {
  const _PlaceholderView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            color: AppTheme.textHint,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Esta sección estará disponible próximamente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Shown inside the lyrics panel when no track is loaded.
class _NoTrackLyricsPlaceholder extends StatelessWidget {
  const _NoTrackLyricsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lyrics_outlined,
              size: 48,
              color: AppTheme.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'Play a track to see lyrics',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
