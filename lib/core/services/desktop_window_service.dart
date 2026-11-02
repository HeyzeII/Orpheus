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
  /// 1. Saves current window size and position (safely handled on Wayland).
  /// 2. Sets minimum size to [kMiniPlayerMinSize].
  /// 3. On Linux (Wayland), sets maximum size to [kMiniPlayerSize] to enforce
  ///    a strict size lock that Wayland compositors respect.
  /// 4. Sets window size to [kMiniPlayerSize].
  /// 5. Disables window resizing (`setResizable(false)`).
  /// 6. Activates "Always on Top" (`setAlwaysOnTop(true)`).
  /// 7. Updates [isMiniPlayerNotifier].
  Future<void> enterMiniPlayer() async {
    if (!isDesktop || isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        _savedWindowSize = await windowManager.getSize();
        try {
          _savedWindowPosition = await windowManager.getPosition();
        } catch (e) {
          DebugLogger.log(
            'DesktopWindowService: getPosition not supported or failed on Wayland: $e',
          );
        }

        await windowManager.setMinimumSize(kMiniPlayerMinSize);
        // On Wayland, lock both min and max to enforce a fixed compact geometry
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
  /// Flow adapted to the Wayland/Mutter async lifecycle:
  /// 1. Deactivates "Always on Top" (`setAlwaysOnTop(false)`).
  /// 2. Restores window shadow (`setHasShadow(true)`).
  /// 3. Clears maximum size hint on Linux using `Size(-1, -1)` so the C++ plugin
  ///    clears `GDK_HINT_MAX_SIZE`.
  /// 4. Restores standard minimum size to [kStandardMinSize].
  /// 5. Re-enables window resizing (`setResizable(true)`).
  /// 6. Awaits a brief asynchronous pause (50ms) to allow GTK and Mutter to
  ///    negotiate the `xdg_toplevel` configure cycle and refresh CSD border input regions.
  /// 7. Restores saved window size (`setSize(_savedWindowSize)`).
  /// 8. Restores saved window position wrapped safely in try-catch (Wayland does
  ///    not allow programmatic absolute positioning).
  /// 9. Updates [isMiniPlayerNotifier].
  Future<void> exitMiniPlayer() async {
    if (!isDesktop || !isMiniPlayerActive) return;

    if (_canInvokeNativeWindow) {
      try {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setHasShadow(true);

        // ── 1. Clear maximum size hint using strictly negative dimensions ───
        // In the Linux C++ plugin, passing negative values turns off the
        // GDK_HINT_MAX_SIZE bitmask. Passing Size.zero would clamp max_size to 0x0
        // and freeze Mutter resize handles.
        if (Platform.isLinux) {
          await windowManager.setMaximumSize(const Size(-1, -1));
        }

        // ── 2. Restore standard minimum size ───────────────────────────────
        await windowManager.setMinimumSize(kStandardMinSize);

        // ── 3. Re-enable window resizing ───────────────────────────────────
        await windowManager.setResizable(true);

        // ── 4. Async yield for Wayland/Mutter CSD configure event ───────────
        // Gives GTK and the Wayland compositor time to process the xdg_toplevel
        // configure cycle and update client-side decoration input regions.
        await Future.delayed(const Duration(milliseconds: 50));

        // ── 5. Restore saved window size and position safely ───────────────
        await windowManager.setSize(_savedWindowSize);
        if (_savedWindowPosition != null) {
          try {
            await windowManager.setPosition(_savedWindowPosition!);
          } catch (e) {
            DebugLogger.log(
              'DesktopWindowService: setPosition not supported or failed on Wayland: $e',
            );
          }
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
