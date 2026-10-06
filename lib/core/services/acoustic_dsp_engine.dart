import 'dart:math' as math;
import 'dart:typed_data';

/// Immutable container holding the 3 core acoustic vector descriptors.
class AcousticDescriptors {
  const AcousticDescriptors({
    required this.rmsEnergy,
    required this.peakDensity,
    required this.spectralBalance,
  });

  /// Root Mean Square energy normalized in [0.0, 1.0].
  final double rmsEnergy;

  /// Rhythmic / transient attack density normalized in [0.0, 1.0].
  final double peakDensity;

  /// Zero-Crossing Rate spectral brightness normalized in [0.0, 1.0].
  final double spectralBalance;

  /// Default fallback descriptors for silent or unscannable tracks.
  static const empty = AcousticDescriptors(
    rmsEnergy: 0.0,
    peakDensity: 0.0,
    spectralBalance: 0.0,
  );

  @override
  String toString() =>
      'AcousticDescriptors(rms: ${rmsEnergy.toStringAsFixed(3)}, peak: ${peakDensity.toStringAsFixed(3)}, spectral: ${spectralBalance.toStringAsFixed(3)})';
}

/// Pure math / DSP calculation engine for PCM audio buffers.
///
/// Designed to run with zero dependencies and zero heap allocations inside
/// background worker isolates.
class AcousticDspEngine {
  const AcousticDspEngine._();

  /// Calculates Root Mean Square (RMS) energy normalized to [0.0, 1.0].
  ///
  /// Expected input: [pcmSamples] normalized in [-1.0, 1.0].
  /// Standard full-scale sine wave has RMS = 1 / sqrt(2) ≈ 0.7071.
  static double calculateRmsEnergy(Float32List pcmSamples) {
    final len = pcmSamples.length;
    if (len == 0) return 0.0;

    double sumSq = 0.0;
    for (int i = 0; i < len; i++) {
      final sample = pcmSamples[i];
      sumSq += sample * sample;
    }

    final rms = math.sqrt(sumSq / len);
    // Normalize such that RMS of full-scale sine (~0.707) maps cleanly near 1.0
    final normalized = rms / 0.7071;
    return normalized.clamp(0.0, 1.0);
  }

  /// Calculates transient and rhythmic peak density normalized to [0.0, 1.0].
  ///
  /// Detects attack peaks exceeding an adaptive threshold (1.4x local RMS)
  /// with a 50ms refractory period to avoid double-counting resonant transients.
  static double calculatePeakDensity(
    Float32List pcmSamples,
    double rmsEnergy, {
    int sampleRate = 44100,
  }) {
    final len = pcmSamples.length;
    if (len == 0 || sampleRate <= 0) return 0.0;

    final durationSec = len / sampleRate;
    if (durationSec <= 0.001) return 0.0;

    // Minimum detection threshold to avoid triggering on background noise
    final threshold = math.max(0.05, rmsEnergy * 0.7071 * 1.4);
    final refractorySamples = (sampleRate * 0.050).round(); // 50ms

    int peakCount = 0;
    int samplesSinceLastPeak = refractorySamples;

    for (int i = 0; i < len; i++) {
      samplesSinceLastPeak++;
      final absVal = pcmSamples[i].abs();

      if (absVal >= threshold && samplesSinceLastPeak >= refractorySamples) {
        peakCount++;
        samplesSinceLastPeak = 0;
      }
    }

    final peaksPerSecond = peakCount / durationSec;
    // Fast rhythmic music (drums, EDM, metal) typically hits 4 - 6 peaks/sec
    const maxExpectedPeaksPerSec = 6.0;
    final normalized = peaksPerSecond / maxExpectedPeaksPerSec;
    return normalized.clamp(0.0, 1.0);
  }

  /// Calculates spectral balance via Zero-Crossing Rate (ZCR) normalized to [0.0, 1.0].
  ///
  /// Higher ZCR correlates with high-frequency dominance (air, hi-hats, distortion),
  /// while lower ZCR correlates with warm, bass-heavy acoustic tones.
  static double calculateSpectralBalance(Float32List pcmSamples) {
    final len = pcmSamples.length;
    if (len < 2) return 0.0;

    int zeroCrossings = 0;
    for (int i = 1; i < len; i++) {
      final prev = pcmSamples[i - 1];
      final curr = pcmSamples[i];
      if ((prev >= 0.0 && curr < 0.0) || (prev < 0.0 && curr >= 0.0)) {
        zeroCrossings++;
      }
    }

    final zcr = zeroCrossings / (len - 1);
    // ZCR typically ranges from 0.01 (sub bass) to 0.20 (bright/percussive)
    const zcrScale = 6.0;
    final normalized = zcr * zcrScale;
    return normalized.clamp(0.0, 1.0);
  }

  /// Analyzes a single PCM buffer and returns all 3 computed descriptors.
  static AcousticDescriptors analyzePcm(
    Float32List pcmSamples, {
    int sampleRate = 44100,
  }) {
    if (pcmSamples.isEmpty) return AcousticDescriptors.empty;

    final rms = calculateRmsEnergy(pcmSamples);
    final peak = calculatePeakDensity(pcmSamples, rms, sampleRate: sampleRate);
    final spectral = calculateSpectralBalance(pcmSamples);

    return AcousticDescriptors(
      rmsEnergy: rms,
      peakDensity: peak,
      spectralBalance: spectral,
    );
  }

  /// Merges multiple descriptor measurements by taking their arithmetic mean.
  static AcousticDescriptors average(List<AcousticDescriptors> list) {
    if (list.isEmpty) return AcousticDescriptors.empty;
    if (list.length == 1) return list.first;

    double totalRms = 0.0;
    double totalPeak = 0.0;
    double totalSpectral = 0.0;

    for (final d in list) {
      totalRms += d.rmsEnergy;
      totalPeak += d.peakDensity;
      totalSpectral += d.spectralBalance;
    }

    final count = list.length;
    return AcousticDescriptors(
      rmsEnergy: (totalRms / count).clamp(0.0, 1.0),
      peakDensity: (totalPeak / count).clamp(0.0, 1.0),
      spectralBalance: (totalSpectral / count).clamp(0.0, 1.0),
    );
  }
}
