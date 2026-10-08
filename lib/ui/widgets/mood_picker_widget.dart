import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/services/audio_player_service.dart';
import '../../core/services/recommendation_engine_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// An interactive mood-picker card that lets the user generate a curated
/// playlist by selecting acoustic parameters (Energy & Brightness) via sliders.
///
/// Designed to be embedded in [HomeView] or as a standalone bottom sheet.
class MoodPickerWidget extends StatefulWidget {
  const MoodPickerWidget({super.key});

  @override
  State<MoodPickerWidget> createState() => _MoodPickerWidgetState();
}

class _MoodPickerWidgetState extends State<MoodPickerWidget> {
  /// RMS Energy → `targetRms` in [RecommendationEngineService.getMoodPlaylist].
  double _energy = 0.5;

  /// Peak Density → `targetEnergy` in [RecommendationEngineService.getMoodPlaylist].
  double _density = 0.5;

  /// Spectral Balance → `targetSpectral`.
  double _spectral = 0.5;

  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ── Slider helpers ─────────────────────────────────────────────────────────

  void _onEnergyChanged(double v) {
    setState(() => _energy = v);
    _scheduleDebounce();
  }

  void _onDensityChanged(double v) {
    setState(() => _density = v);
    _scheduleDebounce();
  }

  void _onSpectralChanged(double v) {
    setState(() => _spectral = v);
    _scheduleDebounce();
  }

  void _scheduleDebounce() {
    _debounce?.cancel();
    // 300 ms debounce: prevents Isar queries on every slider frame.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // Future: update a preview count here when needed.
    });
  }

  void _applyPreset(String name, {required double energy, required double density, required double spectral}) {
    setState(() {
      _energy = energy;
      _density = density;
      _spectral = spectral;
    });
    _scheduleDebounce();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _createSession() async {
    setState(() => _isLoading = true);
    try {
      final tracks = await RecommendationEngineService.instance.getMoodPlaylist(
        targetRms: _energy,
        targetEnergy: _density,
        targetSpectral: _spectral,
        count: 30,
      );

      if (!mounted) return;

      if (tracks.isEmpty) {
        AppToast.showText(
          context,
          'No se encontraron pistas para este ánimo. Prueba otros parámetros.',
          icon: Icons.tune_rounded,
        );
        return;
      }

      await AudioPlayerService.instance.loadPlaylist(
        tracks,
        contextName: 'Sesión de Ánimo',
      );
      // Mood sessions are not radio — clear the radio badge.
      AudioPlayerService.isRadioActiveNotifier.value = false;

      if (mounted) {
        AppToast.showText(
          context,
          '${tracks.length} pistas cargadas para tu sesión de ánimo.',
          icon: Icons.check_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppTheme.accent, size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'SESIÓN POR ÁNIMO',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick Presets Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetChip(
                  label: 'Workout',
                  emoji: '⚡',
                  isSelected: (_energy - 0.90).abs() < 0.05 && (_density - 0.85).abs() < 0.05,
                  onTap: () => _applyPreset('Workout', energy: 0.90, density: 0.85, spectral: 0.70),
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Chill',
                  emoji: '🌙',
                  isSelected: (_energy - 0.25).abs() < 0.05 && (_density - 0.30).abs() < 0.05,
                  onTap: () => _applyPreset('Chill', energy: 0.25, density: 0.30, spectral: 0.35),
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Focus',
                  emoji: '🎯',
                  isSelected: (_energy - 0.40).abs() < 0.05 && (_density - 0.45).abs() < 0.05,
                  onTap: () => _applyPreset('Focus', energy: 0.40, density: 0.45, spectral: 0.50),
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Acústico',
                  emoji: '🎸',
                  isSelected: (_energy - 0.50).abs() < 0.05 && (_density - 0.35).abs() < 0.05,
                  onTap: () => _applyPreset('Acústico', energy: 0.50, density: 0.35, spectral: 0.40),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Energy slider
          _SliderRow(
            label: 'Energía',
            value: _energy,
            lowLabel: '🔇 Tranquilo',
            highLabel: '⚡ Intenso',
            onChanged: _onEnergyChanged,
          ),
          const SizedBox(height: 16),

          // Density / Rhythm slider
          _SliderRow(
            label: 'Ritmo',
            value: _density,
            lowLabel: '🌊 Suave',
            highLabel: '🥁 Percusivo',
            onChanged: _onDensityChanged,
          ),
          const SizedBox(height: 16),

          // Spectral / Brightness slider
          _SliderRow(
            label: 'Brillo',
            value: _spectral,
            lowLabel: '🌙 Cálido',
            highLabel: '☀️ Brillante',
            onChanged: _onSpectralChanged,
          ),
          const SizedBox(height: 24),

          // Launch button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _isLoading ? null : _createSession,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.bgDeep,
                      ),
                    )
                  : const Icon(Icons.shuffle_rounded, size: 18),
              label: Text(_isLoading ? 'Generando...' : 'Crear Sesión'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.lowLabel,
    required this.highLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String lowLabel;
  final String highLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: AppTheme.accent.withValues(alpha: 0.85),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: AppTheme.accent.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              lowLabel,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            Text(
              highLabel,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accent.withValues(alpha: 0.60)
                  : Colors.white.withValues(alpha: 0.10),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.accent : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

