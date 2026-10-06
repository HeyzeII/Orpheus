import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'acoustic_dsp_engine.dart';

/// Task description sent from main isolate to the background acoustic worker.
class ScanTask {
  const ScanTask({
    required this.trackId,
    required this.filePath,
    required this.durationSec,
  });

  final String trackId;
  final String filePath;
  final int durationSec;
}

/// Result returned from background acoustic worker to the main isolate.
class ScanResult {
  const ScanResult({
    required this.trackId,
    required this.rmsEnergy,
    required this.peakDensity,
    required this.spectralBalance,
    required this.success,
    this.errorMessage,
  });

  final String trackId;
  final double rmsEnergy;
  final double peakDensity;
  final double spectralBalance;
  final bool success;
  final String? errorMessage;

  static ScanResult failure(String trackId, String error) => ScanResult(
        trackId: trackId,
        rmsEnergy: 0.0,
        peakDensity: 0.0,
        spectralBalance: 0.0,
        success: false,
        errorMessage: error,
      );
}

/// High-performance chunk extractor for media files.
///
/// Reads 3 strategic 3-second micro-chunks (15s, 50%, 80%) using positional
/// random-access seeking without loading entire media files into memory.
class AcousticChunkExtractor {
  const AcousticChunkExtractor._();

  /// Analyzes the file at [filePath] and extracts average acoustic descriptors.
  static Future<AcousticDescriptors> extractDescriptors({
    required String filePath,
    required int durationSec,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Media file not found on disk', filePath);
    }

    final totalDuration = math.max(1, durationSec);
    final isWav = filePath.toLowerCase().endsWith('.wav');

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final fileLength = await raf.length();
      if (fileLength < 256) {
        return AcousticDescriptors.empty;
      }

      // Compute 3 anchor timestamps:
      // Chunk A: 15s (or 10% for very short tracks)
      // Chunk B: 50% (midpoint / climax)
      // Chunk C: 80% (resolution)
      final t1 = totalDuration > 20 ? 15.0 : totalDuration * 0.1;
      final t2 = totalDuration * 0.5;
      final t3 = totalDuration * 0.8;

      final chunkPoints = [t1, t2, t3];
      final List<AcousticDescriptors> chunkDescriptors = [];

      if (isWav) {
        final wavHeader = await _readWavHeader(raf);
        for (final t in chunkPoints) {
          final pcm = await _readWavChunk(
            raf,
            targetTimeSec: t,
            totalDurationSec: totalDuration,
            header: wavHeader,
            fileLength: fileLength,
          );
          if (pcm.isNotEmpty) {
            chunkDescriptors.add(
              AcousticDspEngine.analyzePcm(pcm, sampleRate: wavHeader.sampleRate),
            );
          }
        }
      } else {
        // Generic compressed audio stream reader (MP3, FLAC, M4A, OGG)
        // Samples PCM approximations via positional bit-chunk sampling
        final avgByteRate = (fileLength / totalDuration).round();
        const chunkSizeSec = 3.0;
        final targetChunkBytes = math.min(131072, (avgByteRate * chunkSizeSec).round()); // max 128KB per chunk

        for (final t in chunkPoints) {
          final targetOffset = (t * avgByteRate)
              .round()
              .clamp(0, math.max(0, fileLength - targetChunkBytes))
              .toInt();
          await raf.setPosition(targetOffset);
          final bytes = await raf.read(targetChunkBytes);
          final pcm = _convertBytesToPcm(bytes);
          if (pcm.isNotEmpty) {
            chunkDescriptors.add(
              AcousticDspEngine.analyzePcm(pcm, sampleRate: 44100),
            );
          }
        }
      }

      if (chunkDescriptors.isEmpty) {
        return AcousticDescriptors.empty;
      }

      return AcousticDspEngine.average(chunkDescriptors);
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  // ── WAV Format Parsing ─────────────────────────────────────────────────────

  static Future<_WavHeader> _readWavHeader(RandomAccessFile raf) async {
    await raf.setPosition(0);
    final headerBytes = await raf.read(44);
    if (headerBytes.length < 44) {
      return _WavHeader.defaultPcm();
    }

    final data = ByteData.sublistView(headerBytes);
    final numChannels = data.getUint16(22, Endian.little);
    final sampleRate = data.getUint32(24, Endian.little);
    final byteRate = data.getUint32(28, Endian.little);
    final blockAlign = data.getUint16(32, Endian.little);
    final bitsPerSample = data.getUint16(34, Endian.little);

    return _WavHeader(
      numChannels: numChannels > 0 ? numChannels : 2,
      sampleRate: sampleRate > 0 ? sampleRate : 44100,
      byteRate: byteRate > 0 ? byteRate : 176400,
      blockAlign: blockAlign > 0 ? blockAlign : 4,
      bitsPerSample: bitsPerSample > 0 ? bitsPerSample : 16,
      dataOffset: 44,
    );
  }

  static Future<Float32List> _readWavChunk(
    RandomAccessFile raf, {
    required double targetTimeSec,
    required int totalDurationSec,
    required _WavHeader header,
    required int fileLength,
  }) async {
    const chunkDurationSec = 3;
    final bytesPerSec = header.sampleRate * header.numChannels * (header.bitsPerSample ~/ 8);
    final chunkByteLength = math.min(bytesPerSec * chunkDurationSec, 529200); // ~516KB max

    final startByteOffset = (header.dataOffset + (targetTimeSec * bytesPerSec).round())
        .clamp(header.dataOffset, math.max(header.dataOffset, fileLength - chunkByteLength))
        .toInt();

    await raf.setPosition(startByteOffset);
    final rawBytes = await raf.read(chunkByteLength);
    return _convertWavBytesToPcm(rawBytes, header);
  }

  static Float32List _convertWavBytesToPcm(Uint8List bytes, _WavHeader header) {
    final bytesPerSample = header.bitsPerSample ~/ 8;
    final totalSamples = bytes.length ~/ (bytesPerSample * header.numChannels);
    if (totalSamples <= 0) return Float32List(0);

    final pcm = Float32List(totalSamples);
    final byteData = ByteData.sublistView(bytes);

    int byteIdx = 0;
    for (int i = 0; i < totalSamples; i++) {
      if (byteIdx + (bytesPerSample * header.numChannels) > bytes.length) break;

      double sampleVal = 0.0;
      if (bytesPerSample == 2) {
        // 16-bit signed integer
        final left = byteData.getInt16(byteIdx, Endian.little);
        if (header.numChannels == 2) {
          final right = byteData.getInt16(byteIdx + 2, Endian.little);
          sampleVal = ((left + right) / 2.0) / 32768.0;
        } else {
          sampleVal = left / 32768.0;
        }
      } else if (bytesPerSample == 3) {
        // 24-bit signed integer
        final b0 = bytes[byteIdx];
        final b1 = bytes[byteIdx + 1];
        final b2 = bytes[byteIdx + 2];
        var val = (b2 << 24) | (b1 << 16) | (b0 << 8);
        val = val >> 8; // sign extend
        sampleVal = val / 8388608.0;
      } else if (bytesPerSample == 4) {
        // 32-bit float
        sampleVal = byteData.getFloat32(byteIdx, Endian.little).toDouble();
      }

      pcm[i] = sampleVal.clamp(-1.0, 1.0);
      byteIdx += bytesPerSample * header.numChannels;
    }

    return pcm;
  }

  static Float32List _convertBytesToPcm(Uint8List bytes) {
    final num16BitSamples = bytes.length ~/ 2;
    if (num16BitSamples <= 0) return Float32List(0);

    final pcm = Float32List(num16BitSamples);
    final byteData = ByteData.sublistView(bytes);

    for (int i = 0; i < num16BitSamples; i++) {
      final sample16 = byteData.getInt16(i * 2, Endian.little);
      pcm[i] = (sample16 / 32768.0).clamp(-1.0, 1.0);
    }

    return pcm;
  }
}

class _WavHeader {
  const _WavHeader({
    required this.numChannels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataOffset,
  });

  final int numChannels;
  final int sampleRate;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;
  final int dataOffset;

  factory _WavHeader.defaultPcm() => const _WavHeader(
        numChannels: 2,
        sampleRate: 44100,
        byteRate: 176400,
        blockAlign: 4,
        bitsPerSample: 16,
        dataOffset: 44,
      );
}

/// Entry point function executed inside the spawned background Isolate.
void acousticScannerWorkerEntryPoint(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((dynamic message) async {
    if (message is ScanTask) {
      try {
        final descriptors = await AcousticChunkExtractor.extractDescriptors(
          filePath: message.filePath,
          durationSec: message.durationSec,
        );

        sendPort.send(
          ScanResult(
            trackId: message.trackId,
            rmsEnergy: descriptors.rmsEnergy,
            peakDensity: descriptors.peakDensity,
            spectralBalance: descriptors.spectralBalance,
            success: true,
          ),
        );
      } catch (e) {
        sendPort.send(
          ScanResult.failure(
            message.trackId,
            e.toString(),
          ),
        );
      }
    }
  });
}
