import 'package:flutter/material.dart';

/// Orpheus premium dark theme inspired by Tidal's aesthetic.
///
/// Design tokens are defined as static constants so they can be referenced
/// from any widget without touching the [ThemeData] lookup.
abstract final class AppTheme {
  // ── Color Palette ──────────────────────────────────────────────────────────

  /// Deepest background — used for the window canvas.
  static const Color bgDeep = Color(0xFF0A0A0A);

  /// Secondary surface — cards, sidebars, player bar.
  static const Color bgSurface = Color(0xFF161616);

  /// Sidebar tint — slightly elevated from bgDeep for subtle separation.
  static const Color bgSidebar = Color(0xFF121212);

  /// Hover / subtle highlight state.
  static const Color bgHover = Color(0xFF1E1E1E);

  /// Thin divider lines.
  static const Color divider = Color(0xFF242424);

  /// Primary text — pure white for titles.
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text — muted for artists/timestamps.
  static const Color textSecondary = Color(0xFF8A8A8A);

  /// Disabled / placeholder text.
  static const Color textHint = Color(0xFF4A4A4A);

  /// Electric cyan accent — used for active states, progress bars, glows.
  static const Color accent = Color(0xFF00E5FF);

  /// Dimmed accent for toggled-off interactive elements.
  static const Color accentDim = Color(0xFF004D57);

  // ── Typography ─────────────────────────────────────────────────────────────

  /// Default text style for body copy.
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    letterSpacing: 0.1,
  );

  // ── ThemeData factory ──────────────────────────────────────────────────────

  static ThemeData build() {
    const colorScheme = ColorScheme.dark(
      surface: bgDeep,
      surfaceContainerHighest: bgSurface,
      primary: accent,
      secondary: accent,
      onPrimary: bgDeep,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgDeep,
      fontFamily: 'Inter',

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDeep,
        foregroundColor: textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: divider,
        thumbColor: accent,
        overlayColor: accent.withAlpha(0x28),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),

      // Icon
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 20,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 0,
      ),

      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(divider),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(2),
      ),

      // Text
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.0,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.1,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
          letterSpacing: 0.2,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          letterSpacing: 0.1,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          letterSpacing: 0.3,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textHint,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
