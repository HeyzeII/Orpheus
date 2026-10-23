import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

/// A custom glassmorphic Client-Side Decoration (CSD) title bar for desktop
/// platforms (Linux, macOS, and Windows).
///
/// Features:
/// - 36.0 px compact height with backdrop blur (glassmorphism).
/// - [DragToMoveArea] for seamless window dragging.
/// - Double-click to toggle maximize/unmaximize.
/// - Platform-adaptive window control buttons (Minimize, Maximize/Restore, Close)
///   with hover effects on Linux/Windows.
/// - Traffic-light clearance on macOS to prevent overlapping native controls.
class DesktopTitleBar extends StatefulWidget implements PreferredSizeWidget {
  const DesktopTitleBar({super.key});

  static const double kHeight = 36.0;

  @override
  Size get preferredSize => const Size.fromHeight(kHeight);

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      _checkMaximizedState();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  bool get _isDesktop {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  Future<void> _checkMaximizedState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = maximized);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  Future<void> _handleMinimize() async {
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  Future<void> _handleToggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  Future<void> _handleClose() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isMacOS = Platform.isMacOS;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: DesktopTitleBar.kHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF141416).withOpacity(0.85),
            border: const Border(
              bottom: BorderSide(
                color: AppTheme.divider,
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left: Traffic lights clearance (macOS) or Brand icon/label ──
              if (isMacOS)
                const SizedBox(width: 78.0)
              else
                _buildBranding(),

              // ── Center: Draggable title region ──
              Expanded(
                child: DragToMoveArea(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 14,
                          color: AppTheme.accent.withOpacity(0.9),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Orpheus',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: Colors.white.withOpacity(0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Right: Custom window buttons (Linux & Windows) ──
              if (!isMacOS)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WindowCaptionButton(
                      icon: Icons.remove_rounded,
                      iconSize: 15,
                      tooltip: 'Minimizar',
                      onPressed: _handleMinimize,
                    ),
                    _WindowCaptionButton(
                      icon: _isMaximized
                          ? Icons.filter_none_rounded
                          : Icons.crop_square_rounded,
                      iconSize: _isMaximized ? 12 : 14,
                      tooltip: _isMaximized ? 'Restaurar' : 'Maximizar',
                      onPressed: _handleToggleMaximize,
                    ),
                    _WindowCaptionButton(
                      icon: Icons.close_rounded,
                      iconSize: 15,
                      isClose: true,
                      tooltip: 'Cerrar',
                      onPressed: _handleClose,
                    ),
                  ],
                )
              else
                const SizedBox(width: 16.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranding() {
    return DragToMoveArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'ORPHEUS',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A minimalist, hoverable window caption button for desktop title bars.
class _WindowCaptionButton extends StatefulWidget {
  const _WindowCaptionButton({
    required this.icon,
    required this.onPressed,
    this.iconSize = 14,
    this.isClose = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final bool isClose;
  final String? tooltip;

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? const Color(0xFFE81123).withOpacity(0.9)
        : Colors.white.withOpacity(0.08);

    final iconColor = _isHovered
        ? Colors.white
        : Colors.white.withOpacity(0.7);

    final button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44.0,
          alignment: Alignment.center,
          color: _isHovered ? hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: iconColor,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: button,
      );
    }

    return button;
  }
}
