import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../views/expanded_player_view.dart';
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
class DesktopNavigationShell extends StatefulWidget {
  const DesktopNavigationShell({super.key});

  @override
  State<DesktopNavigationShell> createState() => _DesktopNavigationShellState();
}

class _DesktopNavigationShellState extends State<DesktopNavigationShell> with WidgetsBindingObserver {
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

/// Adaptive master selector breakpoint widget.
class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) {
      return const MobileNavigationShell();
    } else {
      return const DesktopNavigationShell();
    }
  }
}

/// Navigation shell layout for mobile (Android).
///
/// Key design decisions:
/// - No [Scaffold.bottomNavigationBar]: navigation + mini-player are merged into
///   a single frosted-glass floating panel positioned at the bottom of a [Stack].
/// - [PopScope] intercepts the Android back button when the [ExpandedPlayerView]
///   is open; pressing back minimises the player instead of closing the app.
class MobileNavigationShell extends StatefulWidget {
  const MobileNavigationShell({super.key});

  @override
  State<MobileNavigationShell> createState() => _MobileNavigationShellState();
}

class _MobileNavigationShellState extends State<MobileNavigationShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _expandedPlayerOpen = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      AudioPlayerService.instance.savePlaybackStateNow();
    }
  }

  // ── Expanded player ───────────────────────────────────────────────────────

  Future<void> _openExpandedPlayer() async {
    setState(() => _expandedPlayerOpen = true);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withAlpha(128),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, _, __) => const ExpandedPlayerView(),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      ),
    );
    if (mounted) setState(() => _expandedPlayerOpen = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0D0D0D),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    // Height of the unified bottom panel (mini-player tile + nav bar row)
    const double miniH = 64;   // mini-player area
    const double navH  = 60;   // nav icons area
    const double panelH = miniH + navH;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        // If the expanded player is open, intercept back and let our code
        // close it; otherwise allow the default system pop.
        canPop: !_expandedPlayerOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _expandedPlayerOpen) {
            Navigator.of(context).pop(); // close the expanded player dialog
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.bgDeep,
          // ── Content scrolls freely beneath the floating panel ──────────
          body: Stack(
            children: [
              // Main page views — padded so content ends above the panel.
              Positioned.fill(
                child: IndexedStack(
                  index: _currentIndex,
                  children: const [
                    HomeView(),
                    _PlaceholderView(label: 'Explorar'),
                    LibraryView(),
                    SettingsView(),
                  ],
                ),
              ),

              // ── Unified frosted-glass bottom panel ────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _UnifiedBottomPanel(
                  panelHeight: panelH,
                  miniPlayerHeight: miniH,
                  navBarHeight: navH,
                  currentIndex: _currentIndex,
                  onNavTap: (i) => setState(() => _currentIndex = i),
                  onMiniPlayerTap: _openExpandedPlayer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The unified frosted-glass panel: mini-player (when active) on top,
/// navigation icons below — both sharing the same blurred/gradient surface.
class _UnifiedBottomPanel extends StatelessWidget {
  const _UnifiedBottomPanel({
    required this.panelHeight,
    required this.miniPlayerHeight,
    required this.navBarHeight,
    required this.currentIndex,
    required this.onNavTap,
    required this.onMiniPlayerTap,
  });

  final double panelHeight;
  final double miniPlayerHeight;
  final double navBarHeight;
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final VoidCallback onMiniPlayerTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: panelHeight + bottomInset,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC0D0D0D),   // ~80% opacity at top
                Color(0xF50D0D0D),   // ~96% opacity at bottom
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Mini-player strip (only when a track is loaded) ─────
              StreamBuilder<Track?>(
                stream: AudioPlayerService.instance.currentTrackStream,
                initialData: AudioPlayerService.instance.currentTrack,
                builder: (context, snap) {
                  final track = snap.data;
                  if (track == null || track.trackId.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _MiniPlayerStrip(
                    track: track,
                    height: miniPlayerHeight,
                    onTap: onMiniPlayerTap,
                  );
                },
              ),

              // ── Nav icons row ───────────────────────────────────────
              SizedBox(
                height: navBarHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavBtn(icon: Icons.home_rounded,           label: 'Inicio',       index: 0, current: currentIndex, onTap: onNavTap),
                    _NavBtn(icon: Icons.explore_rounded,        label: 'Explorar',     index: 1, current: currentIndex, onTap: onNavTap),
                    _NavBtn(icon: Icons.library_music_rounded,  label: 'Biblioteca',   index: 2, current: currentIndex, onTap: onNavTap),
                    _NavBtn(icon: Icons.settings_rounded,       label: 'Ajustes',      index: 3, current: currentIndex, onTap: onNavTap),
                  ],
                ),
              ),

              // System nav bar inset spacer
              SizedBox(height: bottomInset),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact mini-player strip — no individual card background, fits into the
/// blurred panel surface without double-layering colours.
class _MiniPlayerStrip extends StatelessWidget {
  const _MiniPlayerStrip({
    required this.track,
    required this.height,
    required this.onTap,
  });

  final Track track;
  final double height;
  final VoidCallback onTap;

  Widget _coverArt() {
    final path = track.customMetadata.customCoverPath;
    final hasArt = path != null && path.isNotEmpty && File(path).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 40,
        child: hasArt
            ? Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 80)
            : const ColoredBox(
                color: AppTheme.bgHover,
                child: Icon(Icons.music_note_rounded,
                    color: AppTheme.textHint, size: 18),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = AudioPlayerService.instance;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // Row content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _coverArt(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Play/Pause
                  StreamBuilder<bool>(
                    stream: svc.isPlayingStream,
                    initialData: svc.isPlaying,
                    builder: (context, snap) {
                      final playing = snap.data ?? false;
                      return IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        icon: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: AppTheme.accent,
                          size: 28,
                        ),
                        onPressed: () => playing ? svc.pause() : svc.play(),
                      );
                    },
                  ),
                  // Skip next
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                    icon: const Icon(Icons.skip_next_rounded,
                        color: AppTheme.textSecondary, size: 24),
                    onPressed: () => svc.next(),
                  ),
                ],
              ),
            ),
            // Progress stripe — 1.5 px at bottom edge of the strip
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: _MiniProgressStripe(svc: svc),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgressStripe extends StatelessWidget {
  const _MiniProgressStripe({required this.svc});
  final AudioPlayerService svc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: svc.positionStream,
      initialData: svc.position,
      builder: (_, posSnap) => StreamBuilder<Duration>(
        stream: svc.durationStream,
        initialData: svc.duration,
        builder: (_, durSnap) {
          final pos = posSnap.data ?? Duration.zero;
          final dur = durSnap.data ?? Duration.zero;
          final frac = dur.inMilliseconds > 0
              ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
              : 0.0;
          return LayoutBuilder(builder: (_, c) {
            return SizedBox(
              height: 1.5,
              child: Stack(children: [
                Container(color: AppTheme.divider),
                Container(
                    width: c.maxWidth * frac,
                    color: AppTheme.accent.withAlpha(200)),
              ]),
            );
          });
        },
      ),
    );
  }
}

/// Single navigation icon + label button inside the unified bottom panel.
class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: active ? AppTheme.accent : AppTheme.textSecondary,
                size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



