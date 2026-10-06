import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/acoustic_dsp_engine.dart';

class MockLocalDatabaseForAcoustic extends LocalDatabase {
  MockLocalDatabaseForAcoustic() : super.internal();

  final Map<String, Track> tracksMap = {};

  @override
  Future<Track?> getTrackByTrackId(String trackId) async {
    return tracksMap[trackId];
  }

  @override
  Future<void> saveTrack(Track track) async {
    tracksMap[track.trackId] = track;
  }
}

void main() {
  group('AcousticDspEngine Unit Tests', () {
    const sampleRate = 44100;

    test('calculateRmsEnergy returns 0.0 for pure silence', () {
      final silence = Float32List(sampleRate);
      final rms = AcousticDspEngine.calculateRmsEnergy(silence);
      expect(rms, 0.0);
    });

    test('calculateRmsEnergy returns ~1.0 for full-scale sine wave', () {
      final samples = Float32List(sampleRate);
      const freq = 440.0;
      for (int i = 0; i < sampleRate; i++) {
        samples[i] = math.sin(2 * math.pi * freq * (i / sampleRate));
      }

      final rms = AcousticDspEngine.calculateRmsEnergy(samples);
      // Full scale sine RMS is 1/sqrt(2) ≈ 0.7071, which normalizes to 1.0
      expect(rms, closeTo(1.0, 0.02));
    });

    test('calculateRmsEnergy returns proportional value for half-amplitude sine', () {
      final samples = Float32List(sampleRate);
      const freq = 440.0;
      for (int i = 0; i < sampleRate; i++) {
        samples[i] = 0.5 * math.sin(2 * math.pi * freq * (i / sampleRate));
      }

      final rms = AcousticDspEngine.calculateRmsEnergy(samples);
      expect(rms, closeTo(0.5, 0.02));
    });

    test('calculatePeakDensity returns 0.0 for silence and detects explicit pulses', () {
      final silence = Float32List(sampleRate);
      expect(AcousticDspEngine.calculatePeakDensity(silence, 0.0), 0.0);

      // Create a 1-second buffer with 4 distinct transient pulses (every 250ms > 50ms refractory)
      final pulsed = Float32List(sampleRate);
      pulsed[0] = 0.9;
      pulsed[11025] = 0.9;
      pulsed[22050] = 0.9;
      pulsed[33075] = 0.9;

      // With 4 peaks in 1 sec, peaksPerSec = 4.0. Normalized = 4.0 / 6.0 ≈ 0.667
      final peakDensity = AcousticDspEngine.calculatePeakDensity(pulsed, 0.1, sampleRate: sampleRate);
      expect(peakDensity, closeTo(0.667, 0.05));
    });

    test('calculateSpectralBalance distinguishes low frequency vs high frequency', () {
      final lowFreq = Float32List(sampleRate);
      final highFreq = Float32List(sampleRate);

      for (int i = 0; i < sampleRate; i++) {
        lowFreq[i] = math.sin(2 * math.pi * 80.0 * (i / sampleRate)); // 80 Hz sub bass
        highFreq[i] = math.sin(2 * math.pi * 3000.0 * (i / sampleRate)); // 3 kHz bright treble
      }

      final lowBalance = AcousticDspEngine.calculateSpectralBalance(lowFreq);
      final highBalance = AcousticDspEngine.calculateSpectralBalance(highFreq);

      expect(lowBalance, lessThan(0.05));
      expect(highBalance, greaterThan(0.5));
      expect(highBalance, greaterThan(lowBalance));
    });

    test('AcousticDspEngine.average correctly computes arithmetic mean', () {
      const d1 = AcousticDescriptors(rmsEnergy: 0.2, peakDensity: 0.4, spectralBalance: 0.6);
      const d2 = AcousticDescriptors(rmsEnergy: 0.8, peakDensity: 0.6, spectralBalance: 0.4);

      final avg = AcousticDspEngine.average([d1, d2]);

      expect(avg.rmsEnergy, closeTo(0.5, 0.001));
      expect(avg.peakDensity, closeTo(0.5, 0.001));
      expect(avg.spectralBalance, closeTo(0.5, 0.001));
    });
  });

  group('Track model acoustic properties', () {
    test('Track model holds acoustic descriptors properly', () {
      final track = Track()
        ..trackId = 'test_acoustics_1'
        ..filePath = '/music/test.wav'
        ..title = 'Acoustic Test'
        ..rmsEnergy = 0.72
        ..peakDensity = 0.45
        ..spectralBalance = 0.81
        ..isScanned = true;

      expect(track.rmsEnergy, 0.72);
      expect(track.peakDensity, 0.45);
      expect(track.spectralBalance, 0.81);
      expect(track.isScanned, isTrue);
    });
  });
}
