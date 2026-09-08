import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/audio/linked_audio_export_augmenter.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';

void main() {
  group('LinkedAudioExportAugmenter', () {
    late _FakeLinkedAudioClipLoader clipLoader;
    late LinkedAudioExportAugmenter augmenter;

    setUp(() {
      clipLoader = _FakeLinkedAudioClipLoader();
      augmenter = LinkedAudioExportAugmenter(
        linkedAudioClipLoader: clipLoader,
      );
    });

    test('returns the original project when no linked audio file exists',
        () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(minutes: 2),
      );

      final augmentedProject = await augmenter.augment(
        project: project,
        linkedAudioFile: null,
      );

      expect(identical(augmentedProject, project), isTrue);
      expect(clipLoader.loadedFiles, isEmpty);
    });

    test('places audio event at timelineOffset with correct gain', () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(minutes: 2),
        audioEvents: [
          ExportAudioEvent(
            offset: Duration.zero,
            clip: _clip(),
          ),
        ],
      );
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/backing.wav',
        displayName: 'Backing',
        volumePercent: 75,
      );

      final augmentedProject = await augmenter.augment(
        project: project,
        linkedAudioFile: linkedAudioFile,
      );

      expect(clipLoader.loadedFiles, [linkedAudioFile]);
      expect(augmentedProject.audioEvents, hasLength(2));
      expect(augmentedProject.audioEvents.last.offset, Duration.zero);
      expect(augmentedProject.audioEvents.last.gain, 0.75);
      expect(augmentedProject.audioEvents.last.clip, clipLoader.clip);
    });

    test('seeks clip by offsetMilliseconds instead of delaying timeline',
        () async {
      // 1 second clip at 44100 Hz stereo.
      final samples = Float32List(44100 * 2);
      clipLoader.clip = ExportAudioClip(
        samples: samples,
        sampleRate: 44100,
        channelCount: 2,
      );

      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(minutes: 2),
      );
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/backing.wav',
        displayName: 'Backing',
        offsetMilliseconds: 500,
        volumePercent: 100,
      );

      final result = await augmenter.augment(
        project: project,
        linkedAudioFile: linkedAudioFile,
      );

      // Event placed at timelineOffset (0), not delayed by offsetMilliseconds.
      expect(result.audioEvents.last.offset, Duration.zero);

      // Clip seeked: 500ms at 44100 Hz = 22050 frames skipped.
      // Remaining: 44100 - 22050 = 22050 frames = 44100 samples (stereo).
      expect(result.audioEvents.last.clip.samples.length, 22050 * 2);
    });

    test('returns empty clip when seek exceeds clip length', () async {
      // Tiny clip: 2 frames.
      clipLoader.clip = _clip();

      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(minutes: 2),
      );
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/short.wav',
        displayName: 'Short',
        offsetMilliseconds: 5000,
        volumePercent: 100,
      );

      final result = await augmenter.augment(
        project: project,
        linkedAudioFile: linkedAudioFile,
      );

      expect(result.audioEvents.last.clip.samples.length, 0);
    });

    test('trims clip to maxDuration when audio exceeds song length', () async {
      // 1 second clip at 44100 Hz stereo.
      final longSamples = Float32List(44100 * 2);
      clipLoader.clip = ExportAudioClip(
        samples: longSamples,
        sampleRate: 44100,
        channelCount: 2,
      );

      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(seconds: 10),
      );
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/long-audio.wav',
        displayName: 'Long Audio',
        volumePercent: 100,
      );

      final result = await augmenter.augment(
        project: project,
        linkedAudioFile: linkedAudioFile,
        maxDuration: const Duration(milliseconds: 500),
      );

      // 500ms at 44100 Hz = 22050 frames, stereo = 44100 samples.
      final clipSamples = result.audioEvents.last.clip.samples;
      expect(clipSamples.length, 22050 * 2);
    });

    test('does not trim when clip fits within maxDuration', () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(seconds: 10),
      );
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/short.wav',
        displayName: 'Short',
        volumePercent: 100,
      );

      final result = await augmenter.augment(
        project: project,
        linkedAudioFile: linkedAudioFile,
        maxDuration: const Duration(seconds: 60),
      );

      // Original clip is tiny (2 frames) — should not be trimmed.
      expect(result.audioEvents.last.clip, clipLoader.clip);
    });

    test('applies seek before maxDuration trim', () async {
      // 1 second clip at 44100 Hz stereo.
      final longSamples = Float32List(44100 * 2);
      clipLoader.clip = ExportAudioClip(
        samples: longSamples,
        sampleRate: 44100,
        channelCount: 2,
      );

      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(seconds: 10),
      );
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/audio.wav',
        displayName: 'Audio',
        offsetMilliseconds: 800,
        volumePercent: 100,
      );

      final result = await augmenter.augment(
        project: project,
        linkedAudioFile: linkedAudioFile,
        maxDuration: const Duration(milliseconds: 100),
      );

      // Seek: 800ms at 44100 Hz = 35280 frames, remaining: 8820 frames.
      // maxDuration: 100ms = 4410 frames → trim to 4410 frames.
      final clipSamples = result.audioEvents.last.clip.samples;
      expect(clipSamples.length, 4410 * 2);
      // Event at timelineOffset (0), not offset by 800ms.
      expect(result.audioEvents.last.offset, Duration.zero);
    });

    test('throws when linked audio volume percent is outside 0 to 100', () {
      const linkedAudioFile = LinkedAudioFile(
        filePath: '/tmp/backing.wav',
        displayName: 'Backing',
        volumePercent: 120,
      );

      expect(
        () => augmenter.augment(
          project: ResolvedExportProject(
            source: SongExportSource('song-1'),
            duration: const Duration(minutes: 2),
          ),
          linkedAudioFile: linkedAudioFile,
        ),
        throwsArgumentError,
      );
      expect(clipLoader.loadedFiles, isEmpty);
    });
  });
}

class _FakeLinkedAudioClipLoader implements LinkedAudioClipLoader {
  final List<LinkedAudioFile> loadedFiles = [];
  ExportAudioClip clip = _clip();

  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    loadedFiles.add(linkedAudioFile);
    return clip;
  }
}

ExportAudioClip _clip() {
  return ExportAudioClip(
    samples: Float32List.fromList(const [0.25, -0.25, 0.5, -0.5]),
    sampleRate: ExportAudioFormat.defaultSampleRate,
    channelCount: ExportAudioFormat.defaultChannelCount,
  );
}
