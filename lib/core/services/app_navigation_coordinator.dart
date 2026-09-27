import 'package:flutter/material.dart';

import '../../ui/widgets/sidebar.dart';

/// Centralized reactive coordinator for shell navigation, tab switching,
/// and global modal dismissals across mobile and desktop platforms.
class AppNavigationCoordinator {
  AppNavigationCoordinator._();
  static final AppNavigationCoordinator instance = AppNavigationCoordinator._();

  /// Reactive notifier for the active main navigation tab.
  final ValueNotifier<NavDestination> currentDestination =
      ValueNotifier<NavDestination>(NavDestination.home);

  /// Reactive notifier for the desktop lyrics slide-up panel visibility.
  final ValueNotifier<bool> desktopLyricsOpen = ValueNotifier<bool>(false);

  /// Navigates to a target [destination] and closes any overlay panels.
  void navigateTo(NavDestination destination) {
    desktopLyricsOpen.value = false;
    currentDestination.value = destination;
  }

  /// Toggles the desktop slide-up lyrics panel.
  void toggleDesktopLyrics() {
    desktopLyricsOpen.value = !desktopLyricsOpen.value;
  }

  /// Sets the desktop slide-up lyrics panel visibility explicitly.
  void setDesktopLyrics(bool open) {
    desktopLyricsOpen.value = open;
  }

  /// Navigates cleanly to [NavDestination.settings] from any context.
  ///
  /// Safely pops any modal routes (e.g. ExpandedPlayerView on mobile/desktop),
  /// collapses the desktop lyrics panel, and switches the active shell tab.
  void navigateToSettings(BuildContext context) {
    // 1. Close any modal route or sheet (ExpandedPlayerView, dialogs, etc.)
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
    }

    // 2. Hide desktop lyrics panel if open
    desktopLyricsOpen.value = false;

    // 3. Switch main shell tab to settings
    currentDestination.value = NavDestination.settings;
  }
}
