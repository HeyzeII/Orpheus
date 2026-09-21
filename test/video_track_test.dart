import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/track.dart';

void main() {
  group('Video Track Support', () {
    test('Track.isVideo returns true only for FileType.mp4', () {
      final videoTrackMp4 = Track()
        ..filePath = '/storage/videos/music_video.mp4'
        ..fileType = FileType.mp4;
      expect(videoTrackMp4.isVideo, isTrue);

      final audioTrackFlac = Track()
        ..filePath = '/storage/music/song.flac'
        ..fileType = FileType.flac;
      expect(audioTrackFlac.isVideo, isFalse);

      final audioTrackMp3 = Track()
        ..filePath = '/storage/music/song.mp3'
        ..fileType = FileType.mp3;
      expect(audioTrackMp3.isVideo, isFalse);

      final audioTrackM4a = Track()
        ..filePath = '/storage/music/song.m4a'
        ..fileType = FileType.m4a;
      expect(audioTrackM4a.isVideo, isFalse);
    });

    test('Video track supports VIDEO quality label', () {
      final videoTrack = Track()
        ..filePath = '/storage/videos/concert.mp4'
        ..fileType = FileType.mp4
        ..audioQuality = 'VIDEO';
      expect(videoTrack.audioQuality, equals('VIDEO'));
      expect(videoTrack.isVideo, isTrue);
    });
  });
}
