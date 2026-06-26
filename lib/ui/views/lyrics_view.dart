import 'package:flutter/material.dart';

import '../../core/models/track.dart';
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
  const LyricsView({super.key, required this.track});

  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  // ── Services ───────────────────────────────────────────────────────────────
  final _lyricsService = LyricsService.instance;
  final _player = AudioPlayerService.instance;

  // ── State ──────────────────────────────────────────────────────────────────
  Future<String?>? _lyricsFuture;
  List<LyricLine> _lines = const [];
  int _activeIndex = -1;

  final _scrollController = ScrollController();
  bool _userScrolling = false;
  static const _lineHeight = 56.0; // px — each lyric row

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track.trackId != widget.track.trackId) {
      _lines = const [];
      _activeIndex = -1;
      _loadLyrics();
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

  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollToActive(int index) {
    if (!_scrollController.hasClients || _userScrolling) return;
    if (index < 0) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    // Target offset puts the active line in the centre of the viewport.
    final targetOffset = (index * _lineHeight) - (viewportHeight / 2) + (_lineHeight / 2);
    final clamped = targetOffset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1117), AppTheme.bgDeep],
          stops: [0.0, 1.0],
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

          // Parse on first render (or when lyrics change)
          final parsed = LrcParser.parse(raw);
          final isSynced = parsed.isNotEmpty;

          if (isSynced && _lines != parsed) {
            // Schedule state update outside build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onLinesReady(parsed);
            });
          }

          if (isSynced) {
            return _SyncedLyricsBody(
              lines: _lines.isNotEmpty ? _lines : parsed,
              scrollController: _scrollController,
              player: _player,
              onUserScrollStart: () => _userScrolling = true,
              onUserScrollEnd: () {
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) _userScrolling = false;
                });
              },
              onActiveLine: (idx) {
                if (idx != _activeIndex) {
                  setState(() => _activeIndex = idx);
                  _scrollToActive(idx);
                }
              },
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
    required this.player,
    required this.onUserScrollStart,
    required this.onUserScrollEnd,
    required this.onActiveLine,
  });

  final List<LyricLine> lines;
  final ScrollController scrollController;
  final AudioPlayerService player;
  final VoidCallback onUserScrollStart;
  final VoidCallback onUserScrollEnd;
  final ValueChanged<int> onActiveLine;

  @override
  State<_SyncedLyricsBody> createState() => _SyncedLyricsBodyState();
}

class _SyncedLyricsBodyState extends State<_SyncedLyricsBody> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snap) {
        final position = snap.data ?? Duration.zero;
        final activeIdx = LrcParser.activeLineIndex(widget.lines, position);

        // Notify parent — it will scroll and update active index state.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onActiveLine(activeIdx);
        });

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification && n.dragDetails != null) {
              widget.onUserScrollStart();
            }
            if (n is ScrollEndNotification) {
              widget.onUserScrollEnd();
            }
            return false;
          },
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 48),
            itemCount: widget.lines.length,
            itemExtent: _LyricsViewState._lineHeight,
            itemBuilder: (context, i) {
              final line = widget.lines[i];
              final isActive = i == activeIdx;
              final isPast = i < activeIdx;

              return _LyricLineItem(
                line: line,
                isActive: isActive,
                isPast: isPast,
                onTap: () {
                  widget.player.seek(line.timestamp);
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Single lyric line widget
// ════════════════════════════════════════════════════════════════════════════

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
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
    final Color textColor;
    final FontWeight fontWeight;
    final double fontSize;
    final double opacity;

    if (isActive) {
      textColor = AppTheme.accent;
      fontWeight = FontWeight.w700;
      fontSize = 22;
      opacity = 1.0;
    } else if (isPast) {
      textColor = AppTheme.textSecondary;
      fontWeight = FontWeight.w400;
      fontSize = 18;
      opacity = 0.45;
    } else {
      textColor = AppTheme.textPrimary;
      fontWeight = FontWeight.w500;
      fontSize = 18;
      opacity = 0.65;
    }

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: Alignment.centerLeft,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 300),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: textColor,
                height: 1.35,
                shadows: isActive
                    ? [
                        Shadow(
                          color: AppTheme.accent.withAlpha(0x66),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Text(line.text, maxLines: 2, overflow: TextOverflow.ellipsis),
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
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 48),
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
    return Center(
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
    return Center(
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
    );
  }
}
