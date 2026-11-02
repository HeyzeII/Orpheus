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

  /// Initializes desktop window settings, removing native GNOME/Mutter title bars (frameless mode)
  /// and applying soft window shadows.
  Future<void> initialize() async {
    if (!isDesktop || !_canInvokeNativeWindow) return;
    try {
      await windowManager.setAsFrameless();
    } catch (e) {
      DebugLogger.log('DesktopWindowService: setAsFrameless error: $e');
    }
    try {
      await windowManager.setHasShadow(true);
    } catch (e) {
      DebugLogger.log('DesktopWindowService: setHasShadow error: $e');
    }
  }

  /// Enters floating Mini Player mode.
  ///
  /// Protected by strict desktop platform checks and individual try-catch blocks
  /// so that missing native plugins (e.g. on Linux) never halt resizing or state changes.
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        _savedWindowSize = await windowManager.getSize();
      } catch (e) {
        DebugLogger.log('DesktopWindowService: getSize error: $e');
      }

      try {
        _savedWindowPosition = await windowManager.getPosition();
      } catch (_) {}

      // Critical geometry calls: enforce exact dimensions
      try {
        await windowManager.setMinimumSize(kMiniReactorSize);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setMinimumSize error: $e');
      }

      try {
        await windowManager.setSize(kMiniReactorSize);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setSize error: $e');
      }

      // Cosmetic styling calls individually shielded against MissingPluginException on Linux
      try {
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setAlwaysOnTop error: $e');
      }

      try {
        await windowManager.setHasShadow(false);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setHasShadow error: $e');
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

  /// Exits Mini Player mode and restores standard window geometry.
  ///
  /// Protected by strict desktop platform checks and individual try-catch blocks.
  /// Preserves frameless mode without native GNOME/Mutter title bars.
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

      try {
        await windowManager.setAsFrameless();
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setAsFrameless error: $e');
      }

      try {
        await windowManager.setHasShadow(true);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setHasShadow error: $e');
      }

      if (Platform.isLinux) {
        try {
          await windowManager.setMaximumSize(const Size(-1, -1));
        } catch (e) {
          DebugLogger.log('DesktopWindowService: setMaximumSize error: $e');
        }
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

      try {
        await windowManager.setSize(targetSize);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: setSize error: $e');
      }

      if (_savedWindowPosition != null) {
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
  void setMiniPlayerActiveForTesting(bool active) {
    isMiniPlayerNotifier.value = active;
  }
}
