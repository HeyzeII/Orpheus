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

  /// Target exact dimensions for the Mini Player with full Orb Reactor and harmonic waves.
  static const Size kMiniReactorSize = Size(730, 380);

  /// Target compact dimensions for the Mini Player (alias for backwards compatibility).
  static const Size kMiniPlayerSize = kMiniReactorSize;

  /// Minimum window size allowed in Mini Player mode.
  static const Size kMiniPlayerMinSize = kMiniReactorSize;

  /// Standard minimum window size restored when exiting Mini Player.
  static const Size kStandardMinSize = Size(950, 650);

  /// Saved standard window bounds prior to entering Mini Player mode.
  Size _savedWindowSize = const Size(1280, 800);
  Offset? _savedWindowPosition;

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

  /// Enters floating Mini Player mode with rigid 730x380 geometry lock.
  ///
  /// Protected by strict desktop platform checks and individual try-catch blocks
  /// so that missing native plugins (e.g. on Linux) never halt resizing or state changes.
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        final currentSize = await windowManager.getSize();
        if (currentSize.width >= kStandardMinSize.width &&
            currentSize.height >= kStandardMinSize.height) {
          _savedWindowSize = currentSize;
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: getSize error: $e');
      }

      try {
        _savedWindowPosition = await windowManager.getPosition();
      } catch (_) {}

      // 1. Rigorous geometric lock: min == max forces Mutter/Wayland to freeze resize handles
      try {
        await windowManager.setMinimumSize(kMiniReactorSize);
        await windowManager.setMaximumSize(kMiniReactorSize);
        await windowManager.setSize(kMiniReactorSize);
        await windowManager.setResizable(false);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: mini-player geometry lock error: $e');
      }

      // 2. Styling & floating behavior
      try {
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setAlwaysOnTop error: $e');
      }

      if (!Platform.isLinux) {
        try {
          await windowManager.setHasShadow(false);
        } catch (_) {}
      }

      try {
        await windowManager.setAsFrameless();
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setAsFrameless error: $e');
      }
    }

    if (kDebugMode) {
      debugPrint(
        '>>> [Orpheus MiniPlayer] ACTIVADO | Tamaño de Ventana: ${kMiniReactorSize.width}x${kMiniReactorSize.height}',
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

      // 1. Release maximum size constraint FIRST to prevent min > max collision in Mutter
      try {
        if (Platform.isLinux) {
          // Negative dimensions turn off GDK_HINT_MAX_SIZE in window_manager_plugin.cc
          await windowManager.setMaximumSize(const Size(-1, -1));
        } else {
          await windowManager.setMaximumSize(Size.zero);
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: release maximumSize error: $e');
      }

      if (!Platform.isLinux) {
        try {
          await windowManager.setHasShadow(true);
        } catch (_) {}
      }

      // 2. Enable resizability and apply target dimensions
      try {
        await windowManager.setResizable(true);
        await windowManager.setSize(targetSize);
        await windowManager.setMinimumSize(kStandardMinSize);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: exit geometry error: $e');
      }

      if (_savedWindowPosition != null && !Platform.isLinux) {
        // setPosition is unprivileged/no-op on Wayland xdg_toplevel
        try {
          await windowManager.setPosition(_savedWindowPosition!);
        } catch (_) {}
      }

      // 3. Post-commit reassertion for Linux/Wayland:
      // Once Mutter completes the configure/commit cycle for 1280x800, reaffirm
      // kStandardMinSize so GTK's internal size-allocation never overrides it.
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
  void setMiniPlayerActiveForTesting(bool active) {
    isMiniPlayerNotifier.value = active;
  }
}
