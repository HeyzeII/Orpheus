import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/lyrics_service.dart';
import '../../core/utils/lrc_parser.dart';
import '../theme/app_theme.dart';

/// Full-screen synchronized lyrics view for a given [track].
///
/// ## Behaviour
/// - Fetches lyrics via [LyricsService] (offline-first, then LRCLIB).
/// - Parses the raw LRC string with [LrcParser].
/// - Listens to [AudioPlayerService.positionStream] to highlight the active line
///   and auto-scrolls so the active line stays vertically centred.
/// - Tapping a lyric line seeks the player to that timestamp (karaoke jump).
///
/// ## States
/// | State          | What the user sees                                  |
/// |----------------|-----------------------------------------------------|
/// | Loading        | Shimmer-style loading indicator                     |
/// | No lyrics      | Elegant "no lyrics found" card with retry button    |
/// | Network error  | Error card with retry button                        |
/// | Plain lyrics   | Static scrollable text (no timestamps)              |
/// | Synced lyrics  | Auto-scrolling, highlighted, interactive lines      |
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.track,
    this.transparentBackground = false,
    this.showThumbnail = true,
    this.onUserScrollStart,
  });

  final Track track;
  final bool transparentBackground;
  final bool showThumbnail;
  final VoidCallback? onUserScrollStart;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  // ── Services ───────────────────────────────────────────────────────────────
  final _lyricsService = LyricsService.instance;
  final _handler = OrpheusAudioHandler.instance;

  // ── State ──────────────────────────────────────────────────────────────────
  Future<String?>? _lyricsFuture;
  List<LyricLine> _lines = const [];

  final _scrollController = ScrollController();

  // ── LRC parse memo: avoid re-parsing the same raw string on every build ────
  String? _cachedRaw;
  List<LyricLine> _cachedParsed = const [];

  // ── Palette for ambient background ────────────────────────────────────────
  Color? _dominantColor;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
    _extractPalette();
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track.trackId != widget.track.trackId) {
      _lines = const [];
      _dominantColor = null;
      _cachedRaw = null;
      _cachedParsed = const [];
      _loadLyrics();
      _extractPalette();
    }
  }

  void _loadLyrics() {
    setState(() {
      _lyricsFuture = _lyricsService.fetchLyrics(widget.track);
    });
  }

  void _onLinesReady(List<LyricLine> lines) {
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  /// Memoized parse: returns cached result if [raw] hasn't changed.
  List<LyricLine> _parseMemo(String raw) {
    if (raw != _cachedRaw) {
      _cachedRaw = raw;
      _cachedParsed = LrcParser.parse(raw);
    }
    return _cachedParsed;
  }

  Future<void> _extractPalette() async {
    final coverPath = widget.track.customMetadata.customCoverPath;
    if (coverPath == null || coverPath.isEmpty || !File(coverPath).existsSync()) {
      return;
    }
    try {
      final pg = await PaletteGenerator.fromImageProvider(
        FileImage(File(coverPath)),
        maximumColorCount: 16,
      );
      if (mounted) {
        setState(() {
          _dominantColor =
              pg.darkMutedColor?.color ?? pg.dominantColor?.color;
        });
      }
    } catch (_) {
      // Palette extraction is non-critical; silently ignore errors.
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final coverPath = widget.track.customMetadata.customCoverPath;
    final hasArt =
        coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    // Ambient background: blended dominant color or fallback gradient
    final ambientBg = _dominantColor != null
        ? Color.lerp(_dominantColor!, Colors.black, 0.55)!
        : const Color(0xFF0D1117);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: widget.transparentBackground ? Colors.transparent : ambientBg,
        gradient: widget.transparentBackground
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ambientBg, AppTheme.bgDeep],
                stops: const [0.0, 1.0],
              ),
      ),
      child: FutureBuilder<String?>(
        future: _lyricsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LyricsLoadingIndicator();
          }

          if (snapshot.hasError || snapshot.data == null) {
            return _LyricsErrorCard(onRetry: _loadLyrics);
          }

          final raw = snapshot.data!;

          if (raw.isEmpty) {
            return _NoLyricsCard(
              track: widget.track,
              onRetry: () async {
                await _lyricsService.clearCache(widget.track);
                _loadLyrics();
              },
            );
          }

          // Memoized parse — only re-runs when the raw string changes.
          final parsed = _parseMemo(raw);
          final isSynced = parsed.isNotEmpty;

          if (isSynced && _lines != parsed) {
            // Schedule state update outside build.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onLinesReady(parsed);
            });
          }

          if (isSynced) {
            return _SyncedLyricsBody(
              lines: _lines.isNotEmpty ? _lines : parsed,
              scrollController: _scrollController,
              handler: _handler,
              coverPath: hasArt ? coverPath : null,
              showThumbnail: widget.showThumbnail,
              onUserScrollStart: () {
                widget.onUserScrollStart?.call();
              },
              onUserScrollEnd: () {},
              // FIX: Remove setState here — _activeIndex in the parent is only
              // used as a comparison guard. Calling setState on the parent
              // triggers a redundant rebuild of FutureBuilder → _SyncedLyricsBody
              // on every verse change. The child already owns the active state.
              onActiveLine: (_) {},
            );
          }

          // Plain (un-timestamped) lyrics
          return _PlainLyricsBody(plainText: raw);
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Synced lyrics body
// ════════════════════════════════════════════════════════════════════════════

class _SyncedLyricsBody extends StatefulWidget {
  const _SyncedLyricsBody({
    required this.lines,
    required this.scrollController,
    required this.handler,
    required this.onUserScrollStart,
    required this.onUserScrollEnd,
    required this.onActiveLine,
    this.coverPath,
    this.showThumbnail = true,
  });

  final List<LyricLine> lines;
  final ScrollController scrollController;
  final OrpheusAudioHandler handler;
  final VoidCallback onUserScrollStart;
  final VoidCallback onUserScrollEnd;
  final ValueChanged<int> onActiveLine;
  final String? coverPath;
  final bool showThumbnail;

  @override
  State<_SyncedLyricsBody> createState() => _SyncedLyricsBodyState();
}

class _SyncedLyricsBodyState extends State<_SyncedLyricsBody> {
  // ── Scroll state ──────────────────────────────────────────────────────────
  int _activeIndex = -1;

  /// True while the user is manually scrolling; auto-scroll is suppressed.
  bool _isUserScrolling = false;

  /// Timer that re-enables auto-scroll 4 seconds after the last manual drag.
  Timer? _resyncTimer;

  // ── Seek-lock: suppresses positionStream for 300ms after a tap-seek ────────
  /// Prevents the position echo from the old timestamp from overwriting the
  /// optimistic _activeIndex set by the user's tap.
  bool _isSeekingLock = false;
  Timer? _seekLockTimer;

  // ── Per-line GlobalKeys for Scrollable.ensureVisible (height-aware) ───────
  List<GlobalKey> _lineKeys = [];

  // ── Position stream subscription ─────────────────────────────────────────
  StreamSubscription<Duration>? _positionSub;

  // ── Current lines snapshot (updated via didUpdateWidget) ──────────────────
  late List<LyricLine> _lines;

  @override
  void initState() {
    super.initState();
    _lines = widget.lines;
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());

    // Subscribe directly to the player position stream.
    _positionSub = AudioPlayerService.instance.positionStream.listen(_onPosition);

    // Jump to the active verse immediately on first render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final idx = LrcParser.activeLineIndex(_lines, AudioPlayerService.instance.position);
      if (idx >= 0) {
        _activeIndex = idx;
        _scrollToActive(idx, animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(_SyncedLyricsBody old) {
    super.didUpdateWidget(old);
    // Lines changed (new track or late parse result) → rebuild keys and resync.
    if (!identical(old.lines, widget.lines)) {
      _lines = widget.lines;
      _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final idx = LrcParser.activeLineIndex(_lines, AudioPlayerService.instance.position);
        if (idx >= 0) {
          if (mounted) setState(() => _activeIndex = idx);
          if (!_isUserScrolling) _scrollToActive(idx, animate: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _resyncTimer?.cancel();
    _seekLockTimer?.cancel();
    super.dispose();
  }

  // ── Position listener ─────────────────────────────────────────────────────

  void _onPosition(Duration pos) {
    // While seek-lock is active, ignore position echoes from the old timestamp.
    // This prevents the ~4-frame flicker where _activeIndex bounces back to the
    // previous verse before the player confirms the new seek position.
    if (!mounted || _isSeekingLock) return;
    final next = LrcParser.activeLineIndex(_lines, pos);
    if (next != _activeIndex) {
      setState(() => _activeIndex = next);
      widget.onActiveLine(next);
      if (!_isUserScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isUserScrolling) return;
          _scrollToActive(next);
        });
      }
    }
  }

  // ── Scroll helpers ────────────────────────────────────────────────────────

  /// Scrolls so that line [index] sits at ~35% from the top of the viewport.
  ///
  /// Uses [Scrollable.ensureVisible] with a [GlobalKey] so Flutter computes the
  /// real rendered height of each verse (handles word-wrap correctly). Falls
  /// back to a proportional jump + retry if the target is currently offscreen
  /// due to ListView lazy loading.
  void _scrollToActive(int index, {bool animate = true}) {
    if (index < 0 || index >= _lineKeys.length) return;

    final key = _lineKeys[index];
    final ctx = key.currentContext;

    if (ctx != null && widget.scrollController.hasClients) {
      // Happy path: element is in the viewport tree — use real geometry.
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: animate ? const Duration(milliseconds: 450) : Duration.zero,
        curve: Curves.easeInOutCubic,
      );
    } else if (widget.scrollController.hasClients && _lines.isNotEmpty) {
      // Fallback: element is offscreen (lazy load). Jump to an approximate
      // position to bring it into the viewport, then re-run ensureVisible once
      // the element has been laid out in the next frame.
      final maxScroll = widget.scrollController.position.maxScrollExtent;
      final approxOffset = ((index / _lines.length) * maxScroll).clamp(0.0, maxScroll);
      widget.scrollController.jumpTo(approxOffset);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.scrollController.hasClients) return;
        final retryCtx = key.currentContext;
        if (retryCtx != null) {
          Scrollable.ensureVisible(
            retryCtx,
            alignment: 0.35,
            duration: animate ? const Duration(milliseconds: 450) : Duration.zero,
            curve: Curves.easeInOutCubic,
          );
        }
      });
    }
  }

  /// Starts (or restarts) the 4-second countdown before auto-scroll resumes.
  void _startResyncTimer() {
    _resyncTimer?.cancel();
    _resyncTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isUserScrolling) {
        setState(() => _isUserScrolling = false);
        // Re-engage on the current active line.
        _scrollToActive(_activeIndex);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Scroll list with fade edges ────────────────────────────────────
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // Only react to genuine finger drags (not programmatic scrolls).
            if (n is ScrollStartNotification && n.dragDetails != null) {
              if (!_isUserScrolling) {
                setState(() => _isUserScrolling = true);
                widget.onUserScrollStart();
              }
              _startResyncTimer();
            } else if (n is UserScrollNotification &&
                n.direction != ScrollDirection.idle) {
              if (!_isUserScrolling) {
                setState(() => _isUserScrolling = true);
                widget.onUserScrollStart();
              }
              _startResyncTimer();
            }
            return false;
          },
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0.0, 0.08, 0.88, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: widget.scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                top: widget.showThumbnail && widget.coverPath != null ? 140 : 28,
                bottom: 140,
                left: 20,
                right: 20,
              ),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                final isActive = i == _activeIndex;
                final isPast = i < _activeIndex;

                return _LyricLineItem(
                  key: _lineKeys[i],
                  line: line,
                  isActive: isActive,
                  isPast: isPast,
                  onTap: () {
                    debugPrint('LYRIC_TAP: ${line.timestamp}');
                    // Optimistic update: set index and clear user-scroll before
                    // the player confirms the new position.
                    setState(() {
                      _activeIndex = i;
                      _isUserScrolling = false;
                    });
                    widget.onActiveLine(i);

                    // Seek-lock: silence positionStream for 300ms so the old
                    // timestamp echo doesn't flicker _activeIndex back.
                    _seekLockTimer?.cancel();
                    _isSeekingLock = true;
                    _seekLockTimer = Timer(const Duration(milliseconds: 300), () {
                      _isSeekingLock = false;
                    });

                    AudioPlayerService.instance.seek(line.timestamp);
                    _resyncTimer?.cancel();
                    // Use addPostFrameCallback so the newly-active item has been
                    // built at its full size before ensureVisible measures it.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scrollToActive(i);
                    });
                  },
                );
              },
            ),
          ),
        ),

        // ── Miniature cover thumbnail (top-left, 108x108 with translucent border) ──
        // IgnorePointer ensures the thumbnail never blocks tap-to-seek events
        // on the first few lyric lines that overlap with the 108×108 image area.
        if (widget.showThumbnail && widget.coverPath != null)
          Positioned(
            top: 12,
            left: 16,
            child: IgnorePointer(
              child: Container(
                width: 108,
                height: 108,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.file(
                    File(widget.coverPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 216,
                  ),
                ),
              ),
            ),
          ),

        // ── Floating "Resincronizar" button (visible while user scrolling) ──
        AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          bottom: _isUserScrolling ? 24 : -70,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_isUserScrolling,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isUserScrolling ? 1.0 : 0.0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _resyncTimer?.cancel();
                    setState(() => _isUserScrolling = false);
                    _scrollToActive(_activeIndex);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.45),
                          blurRadius: 16,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync_rounded, size: 18, color: Colors.black),
                        SizedBox(width: 8),
                        Text(
                          'Resincronizar',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'Inter',
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Single lyric line widget (AnimatedDefaultTextStyle + AnimatedPadding)
// ════════════════════════════════════════════════════════════════════════════

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    super.key,
    required this.line,
    required this.isActive,
    required this.isPast,
    required this.onTap,
  });

  final LyricLine line;
  final bool isActive;
  final bool isPast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double opacity = isActive ? 1.0 : 0.40;
    final FontWeight fontWeight = isActive ? FontWeight.w800 : FontWeight.w500;
    final double fontSize = isActive ? 30.0 : 22.0;
    // ── Stable padding: same vertical space for every line so the layout
    //    height never jumps and word-wrap never reflows during animation.
    const EdgeInsets stablePadding = EdgeInsets.symmetric(vertical: 10.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('LYRIC_TAP: ${line.timestamp}');
        onTap();
      },
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: stablePadding,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: Colors.white,
                height: 1.35,
                shadows: isActive
                    ? [
                        Shadow(
                          color: AppTheme.accent.withValues(alpha: 0.40),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                line.text,
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Plain (non-synced) lyrics body
// ════════════════════════════════════════════════════════════════════════════

class _PlainLyricsBody extends StatelessWidget {
  const _PlainLyricsBody({required this.plainText});

  final String plainText;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.06, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
          child: Text(
            plainText,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: AppTheme.textPrimary,
              height: 1.8,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Loading indicator
// ════════════════════════════════════════════════════════════════════════════

class _LyricsLoadingIndicator extends StatefulWidget {
  const _LyricsLoadingIndicator();

  @override
  State<_LyricsLoadingIndicator> createState() => _LyricsLoadingIndicatorState();
}

class _LyricsLoadingIndicatorState extends State<_LyricsLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulse,
            child: const Icon(
              Icons.lyrics_outlined,
              size: 48,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Fetching lyrics…',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// "No lyrics" card
// ════════════════════════════════════════════════════════════════════════════

class _NoLyricsCard extends StatelessWidget {
  const _NoLyricsCard({required this.track, required this.onRetry});

  final Track track;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lyrics_outlined, size: 40, color: AppTheme.textHint),
                    const SizedBox(height: 16),
                    Text(
                      'No lyrics found',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'LRCLIB has no entry for\n"${track.displayTitle}"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: const BorderSide(color: AppTheme.accentDim),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Network error card
// ════════════════════════════════════════════════════════════════════════════

class _LyricsErrorCard extends StatelessWidget {
  const _LyricsErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 40,
                      color: AppTheme.textHint,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connection error',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Could not reach LRCLIB.\nCheck your internet connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: const BorderSide(color: AppTheme.accentDim),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
