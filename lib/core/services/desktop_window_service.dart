import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/debug_logger.dart';

/// Singleton service managing window geometry, transitions, and state
/// between standard desktop window mode and the floating Mini Player mode.
class DesktopWindowService {
  DesktopWindowService._internal();

  static final DesktopWindowService instance = DesktopWindowService._internal();

  factory DesktopWindowService() => instance;

  /// Reactive state for whether the application is currently in Mini Player mode.
  final ValueNotifier<bool> isMiniPlayerNotifier = ValueNotifier<bool>(false);

  /// Current Mini Player active state.
  bool get isMiniPlayerActive => isMiniPlayerNotifier.value;

  /// Target compact dimensions for the Mini Player.
  static const Size kMiniPlayerSize = Size(490, 350);

  /// Minimum window size allowed in Mini Player mode.
  static const Size kMiniPlayerMinSize = Size(420, 300);

  /// Standard minimum window size restored when exiting Mini Player.
  static const Size kStandardMinSize = Size(950, 650);

  /// Saved standard window bounds prior to entering Mini Player mode.
  Size _savedWindowSize = const Size(1280, 800);
  Offset? _savedWindowPosition;

  /// Whether current platform supports desktop window manipulation.
  bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  /// Whether native window manager platform channels can be safely invoked
  /// (disabled during headless flutter test execution).
  bool get _canInvokeNativeWindow =>
      isDesktop && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Enters floating Mini Player mode.
  ///
  /// 1. Saves current window size and position.
  /// 2. Sets minimum size to [kMiniPlayerMinSize].
  /// 3. On Linux (Wayland), also sets maximum size to [kMiniPlayerSize] to
  ///    enforce a hard size lock that Wayland compositors (Sway, KDE, Hyprland)
  ///    respect. Without this, `setResizable(false)` alone may be ignored.
  /// 4. Sets window size to [kMiniPlayerSize].
  /// 5. Disables window resizing (`setResizable(false)`).
  /// 6. Activates "Always on Top" (`setAlwaysOnTop(true)`).
  /// 7. Updates [isMiniPlayerNotifier].
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        _savedWindowSize = await windowManager.getSize();
        _savedWindowPosition = await windowManager.getPosition();

        await windowManager.setMinimumSize(kMiniPlayerMinSize);
        // On Wayland, lock both min and max to the same target so compositors
        // that ignore setResizable(false) still honour the fixed size.
        if (Platform.isLinux) {
          await windowManager.setMaximumSize(kMiniPlayerSize);
        }
        await windowManager.setSize(kMiniPlayerSize);
        await windowManager.setResizable(false);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setHasShadow(false);
        await windowManager.setBackgroundColor(Colors.transparent);
      } catch (e) {
        DebugLogger.log('DesktopWindowService: Error entering mini player: $e');
      }
    }

    isMiniPlayerNotifier.value = true;
  }

  /// Exits Mini Player mode and restores standard window geometry.
  ///
  /// Call order is critical on Linux/GTK: the GTK WM ignores `setMinimumSize`
  /// and `setSize` while `resizable=false`, so `setResizable(true)` must be
  /// invoked **first** to unfreeze the compositor before updating hints.
  ///
  /// 1. Deactivates "Always on Top" (`setAlwaysOnTop(false)`).
  /// 2. Restores window shadow (`setHasShadow(true)`).
  /// 3. Re-enables resizing (`setResizable(true)`) — must happen before hint changes.
  /// 4. Restores standard minimum size to [kStandardMinSize].
  /// 5. On Linux, removes the maximum size cap (`setMaximumSize(Size.zero)`).
  /// 6. Restores saved window size and position.
  /// 7. Updates [isMiniPlayerNotifier].
  Future<void> exitMiniPlayer() async {
    if (!isDesktop || !isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setHasShadow(true);

        // ── Unfreeze the GTK/Wayland WM first ──────────────────────────────
        // On Linux, geometry hints are ignored while the window is non-resizable.
        // Calling setResizable(true) before setMinimumSize ensures the compositor
        // accepts the updated constraints and the subsequent setSize call.
        await windowManager.setResizable(true);

        // ── Restore geometry constraints ────────────────────────────────────
        await windowManager.setMinimumSize(kStandardMinSize);
        // Remove the maximum size cap applied on Wayland entry.
        if (Platform.isLinux) {
          await windowManager.setMaximumSize(Size.zero);
        }

        // ── Restore size and position ───────────────────────────────────────
        await windowManager.setSize(_savedWindowSize);
        if (_savedWindowPosition != null) {
          await windowManager.setPosition(_savedWindowPosition!);
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
