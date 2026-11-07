import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/debug_logger.dart';

/// Singleton service managing window geometry and transitions between
/// standard desktop window mode and the compact floating Mini Player mode.
class DesktopWindowService {
  DesktopWindowService._internal();

  static final DesktopWindowService instance = DesktopWindowService._internal();

  factory DesktopWindowService() => instance;

  /// Reactive state for whether the application is currently in Mini Player mode.
  final ValueNotifier<bool> isMiniPlayerNotifier = ValueNotifier<bool>(false);

  /// Current Mini Player active state.
  bool get isMiniPlayerActive => isMiniPlayerNotifier.value;

  /// Standard wide dimensions for Linux & Windows (retaining native decorations and panoramic layout).
  static const Size kMiniReactorSizeDesktop = Size(730, 380);

  /// Compact floating card dimensions for macOS (frameless and tailored for Orb Reactor).
  static const Size kMiniReactorSizeMacOS = Size(600, 360);

  /// Default constant for backward compatibility.
  static const Size kMiniReactorSize = kMiniReactorSizeDesktop;

  /// Target compact dimensions for the Mini Player (alias for backwards compatibility).
  static const Size kMiniPlayerSize = kMiniReactorSizeDesktop;

  /// Minimum window size allowed in Mini Player mode.
  static const Size kMiniPlayerMinSize = kMiniReactorSizeDesktop;

  /// Standard minimum window size restored when exiting Mini Player.
  static const Size kStandardMinSize = Size(950, 650);

  /// Dynamic target dimensions resolved according to current operating system.
  static Size get targetMiniPlayerSize {
    if (!kIsWeb && Platform.isMacOS) {
      return kMiniReactorSizeMacOS;
    }
    return kMiniReactorSizeDesktop;
  }

  /// Saved standard window bounds prior to entering Mini Player mode.
  Size _savedWindowSize = const Size(1280, 800);
  Offset? _savedWindowPosition;
  bool _wasMaximizedBeforeMini = false;

  /// Whether the main window was maximized prior to entering Mini Player mode.
  bool get wasMaximizedBeforeMini => _wasMaximizedBeforeMini;

  /// Strict desktop platform check ensuring Android, iOS and Web are never affected.
  bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  /// Whether native window manager platform channels can be safely invoked
  /// (disabled during headless flutter test execution and on mobile/web).
  bool get _canInvokeNativeWindow =>
      isDesktop && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Initializes desktop window settings for the main window, ensuring resizability
  /// and standard minimum dimensions from startup without forcing any mini-player geometry.
  Future<void> initialize() async {
    if (!isDesktop || !_canInvokeNativeWindow) return;

    // Apply shadow only where supported (macOS and Windows); omitted on Linux to avoid MissingPluginException.
    if (!Platform.isLinux) {
      try {
        await windowManager.setHasShadow(true);
      } catch (_) {}
    }

    try {
      await windowManager.setMinimumSize(kStandardMinSize);
    } catch (e) {
      DebugLogger.log('DesktopWindowService: setMinimumSize error: $e');
    }

    try {
      await windowManager.setResizable(true);
    } catch (e) {
      DebugLogger.log('DesktopWindowService: setResizable error: $e');
    }

    // On Linux/X11/Wayland, re-assert once the compositor has mapped the window
    // to guarantee Mutter/GNOME enforces kStandardMinSize from frame zero.
    if (Platform.isLinux) {
      Future.delayed(const Duration(milliseconds: 100), () async {
        try {
          if (!isMiniPlayerActive) {
            await windowManager.setMinimumSize(kStandardMinSize);
            await windowManager.setResizable(true);
          }
        } catch (_) {}
      });
    }
  }

  /// Enters floating Mini Player mode.
  ///
  /// Protected by strict desktop platform checks and individual try-catch blocks.
  /// On Linux (Wayland/Mutter), avoids runtime decoration changes (setAsFrameless)
  /// and abrupt resizable toggles that destroy the FlView or desynchronize EGL buffers.
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      // 0. Detect and unmaximize if the window was maximized, so Mutter/Wayland does not
      // retain the maximized flag and snap back to full screen when losing focus.
      try {
        _wasMaximizedBeforeMini = await windowManager.isMaximized();
        if (_wasMaximizedBeforeMini) {
          await windowManager.unmaximize();
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: unmaximize error: $e');
      }

      try {
        final currentSize = await windowManager.getSize();
        if (!_wasMaximizedBeforeMini &&
            currentSize.width >= kStandardMinSize.width &&
            currentSize.height >= kStandardMinSize.height) {
          _savedWindowSize = currentSize;
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: getSize error: $e');
      }

      try {
        _savedWindowPosition = await windowManager.getPosition();
      } catch (_) {}

      final miniSize = targetMiniPlayerSize;

      // 1. Lower minimum bounds across all desktop platforms so compositors (Cocoa/NSWindow,
      // Mutter/Wayland, X11) accept miniSize without violating minimum bounds on focus changes.
      try {
        await windowManager.setMinimumSize(miniSize);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setMinimumSize error: $e');
      }

      // 2. On Linux, lock maximumSize to miniSize to prevent Mutter/KWin from expanding the
      // window or re-tiling it upon losing focus.
      if (Platform.isLinux) {
        try {
          await windowManager.setMaximumSize(miniSize);
        } catch (e) {
          DebugLogger.log('DesktopWindowService: setMaximumSize error: $e');
        }
      }

      // 3. Pure geometric resizing (seamless across EGL/Wayland on Linux and macOS)
      try {
        await windowManager.setSize(miniSize);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setSize error: $e');
      }

      // 4. Safe floating behavior
      try {
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setAlwaysOnTop error: $e');
      }

      // 5. Platform-specific styling:
      // On Linux, setAsFrameless() invokes gtk_window_set_decorated(false) which
      // forces GTK to unrealize the window, destroying FlView / FlTaskRunner and
      // causing a segmentation fault. Thus, frameless/shadow are macOS/Windows only.
      if (!Platform.isLinux) {
        try {
          await windowManager.setHasShadow(false);
          await windowManager.setAsFrameless();
          await windowManager.setResizable(false);
        } catch (_) {}
      }
    }

    if (kDebugMode) {
      final miniSize = targetMiniPlayerSize;
      debugPrint(
        '>>> [Orpheus MiniPlayer] ACTIVADO | Tamaño de Ventana: ${miniSize.width}x${miniSize.height}',
      );
    }

    isMiniPlayerNotifier.value = true;
  }

  /// Exits Mini Player mode and cleanly restores main window standard geometry.
  ///
  /// Protected by strict desktop platform checks and individual try-catch blocks.
  Future<void> exitMiniPlayer() async {
    if (!isDesktop || !isMiniPlayerActive) return;

    final targetSize = (_savedWindowSize.width >= kStandardMinSize.width &&
            _savedWindowSize.height >= kStandardMinSize.height)
        ? _savedWindowSize
        : const Size(1280, 800);

    if (_canInvokeNativeWindow) {
      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setAlwaysOnTop error: $e');
      }

      // 1. Release maximum size constraint on Linux (-1, -1 disables GDK_HINT_MAX_SIZE in window_manager_plugin.cc)
      if (Platform.isLinux) {
        try {
          await windowManager.setMaximumSize(const Size(-1, -1));
        } catch (e) {
          DebugLogger.log('DesktopWindowService: release maximumSize error: $e');
        }
      }

      if (!Platform.isLinux) {
        try {
          await windowManager.setResizable(true);
          await windowManager.setHasShadow(true);
          // Re-assert transparent full-size title bar style on macOS to restore
          // native traffic light controls seamlessly over DesktopTitleBar without
          // leaving any persistent gray system title bar or title text.
          await windowManager.setTitleBarStyle(
            TitleBarStyle.hidden,
            windowButtonVisibility: true,
          );
        } catch (_) {}
      }

      // 2. Restore standard dimensions and minimum bounds cleanly
      try {
        if (_wasMaximizedBeforeMini) {
          await windowManager.setMinimumSize(kStandardMinSize);
          await windowManager.maximize();
        } else {
          await windowManager.setSize(targetSize);
          await windowManager.setMinimumSize(kStandardMinSize);
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: exit geometry error: $e');
      }

      if (!_wasMaximizedBeforeMini && _savedWindowPosition != null && !Platform.isLinux) {
        // setPosition is unprivileged/no-op on Wayland xdg_toplevel
        try {
          await windowManager.setPosition(_savedWindowPosition!);
        } catch (_) {}
      }
    }

    if (kDebugMode) {
      debugPrint(
        '>>> [Orpheus MiniPlayer] DESACTIVADO | Restaurado a: ${targetSize.width}x${targetSize.height}',
      );
    }

    isMiniPlayerNotifier.value = false;
  }

  /// Toggles between standard window mode and Mini Player mode.
  Future<void> toggleMiniPlayer() async {
    if (isMiniPlayerActive) {
      await exitMiniPlayer();
    } else {
      await enterMiniPlayer();
    }
  }

  /// For unit testing: sets the active mini player state directly without native window calls.
  @visibleForTesting
  void setMiniPlayerActiveForTesting(bool active, {bool wasMaximized = false}) {
    isMiniPlayerNotifier.value = active;
    _wasMaximizedBeforeMini = wasMaximized;
  }
}
