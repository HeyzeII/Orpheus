import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/debug_logger.dart';

/// Singleton service managing the internal Mini Player view state.
///
/// Native window geometry manipulation and OS-level resizing locks have been
/// removed in favor of internal Flutter layout transitions, keeping the native
/// desktop window always resizable and preventing Wayland/Mutter compositor locks.
class DesktopWindowService {
  DesktopWindowService._internal();

  static final DesktopWindowService instance = DesktopWindowService._internal();

  factory DesktopWindowService() => instance;

  /// Reactive state for whether the application is currently in Mini Player mode.
  final ValueNotifier<bool> isMiniPlayerNotifier = ValueNotifier<bool>(false);

  /// Current Mini Player active state.
  bool get isMiniPlayerActive => isMiniPlayerNotifier.value;

  /// Target compact dimensions for the internal Mini Player view.
  static const Size kMiniPlayerSize = Size(490, 350);

  /// Minimum dimensions for the compact view.
  static const Size kMiniPlayerMinSize = Size(420, 300);

  /// Standard minimum window size recommendation.
  static const Size kStandardMinSize = Size(950, 650);

  /// Whether current platform supports desktop window manipulation.
  bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  /// Whether native window manager platform channels can be safely invoked
  /// (disabled during headless flutter test execution).
  bool get _canInvokeNativeWindow =>
      isDesktop && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Ensures the native OS window remains resizable.
  Future<void> ensureWindowResizable() async {
    if (_canInvokeNativeWindow) {
      try {
        await windowManager.setResizable(true);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: Error setting resizable: $e');
      }
    }
  }

  /// Enters internal Mini Player view mode.
  ///
  /// Changes internal UI state without resizing or locking the native window.
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;
    isMiniPlayerNotifier.value = true;
    await ensureWindowResizable();
  }

  /// Exits internal Mini Player view mode.
  ///
  /// Restores standard UI layout without touching native window bounds.
  Future<void> exitMiniPlayer() async {
    if (!isDesktop || !isMiniPlayerActive) return;
    isMiniPlayerNotifier.value = false;
    await ensureWindowResizable();
  }

  /// Toggles between standard view mode and internal Mini Player mode.
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
