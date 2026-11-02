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
  static const Size kMiniReactorSize = Size(580, 360);

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

  /// Enters floating Mini Player mode.
  ///
  /// Protected by strict desktop platform checks.
  /// 1. Saves current window size and position.
  /// 2. Sets minimum size to [kMiniReactorSize].
  /// 3. Resizes OS window to [kMiniReactorSize].
  /// 4. Hides window decorations (frameless).
  /// 5. Enables "Always on Top".
  /// 6. Updates [isMiniPlayerNotifier].
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        _savedWindowSize = await windowManager.getSize();
        try {
          _savedWindowPosition = await windowManager.getPosition();
        } catch (_) {}

        // Enforce exact mini reactor dimensions for both min size and active size
        await windowManager.setMinimumSize(kMiniReactorSize);
        await windowManager.setSize(kMiniReactorSize);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setHasShadow(false);

        try {
          await windowManager.setAsFrameless();
        } catch (e) {
          DebugLogger.log('DesktopWindowService: setAsFrameless error: $e');
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: Error entering mini player: $e');
      }
    }

    isMiniPlayerNotifier.value = true;
  }

  /// Exits Mini Player mode and restores standard window geometry.
  ///
  /// Protected by strict desktop platform checks.
  /// 1. Deactivates "Always on Top".
  /// 2. Restores window shadow.
  /// 3. Restores window frame and native title bar decorations.
  /// 4. Clears maximum size hints if on Linux.
  /// 5. Restores standard minimum size [kStandardMinSize].
  /// 6. Restores saved window size and position.
  /// 7. Updates [isMiniPlayerNotifier].
  Future<void> exitMiniPlayer() async {
    if (!isDesktop || !isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setHasShadow(true);

        try {
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        } catch (e) {
          DebugLogger.log('DesktopWindowService: setTitleBarStyle error: $e');
        }

        if (Platform.isLinux) {
          await windowManager.setMaximumSize(const Size(-1, -1));
        }

        await windowManager.setMinimumSize(kStandardMinSize);
        await windowManager.setResizable(true);

        final targetSize = (_savedWindowSize.width >= kStandardMinSize.width &&
                _savedWindowSize.height >= kStandardMinSize.height)
            ? _savedWindowSize
            : const Size(1280, 800);

        await windowManager.setSize(targetSize);

        if (_savedWindowPosition != null) {
          try {
            await windowManager.setPosition(_savedWindowPosition!);
          } catch (_) {}
        }
      } catch (e) {
        DebugLogger.log('DesktopWindowService: Error exiting mini player: $e');
      }
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
