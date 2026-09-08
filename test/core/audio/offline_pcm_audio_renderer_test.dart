import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/audio/offline_pcm_audio_renderer.dart';

void main() {
  group('OfflinePcmAudioRenderer', () {
    const format = ExportAudioFormat(sampleRate: 4, channelCount: 2);
    const renderer = OfflinePcmAudioRenderer();

    test('places an audio clip at the requested timeline offset', () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(seconds: 2),
        outputFormat: format,
        audioEvents: [
          ExportAudioEvent(
            offset: const Duration(milliseconds: 500),
            clip: _stereoClip([0.5, -0.5, 0.25, -0.25], format),
          ),
        ],
      );

      final rendered = await renderer.render(project);

      expect(rendered.sampleRate, 4);
      expect(rendered.channelCount, 2);
      expect(
        rendered.samples,
        Float32List.fromList([
          0.0,
          0.0,
          0.0,
          0.0,
          0.5,
          -0.5,
          0.25,
          -0.25,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
        ]),
      );
    });

    test('mixes overlapping events and applies per-event gain', () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(seconds: 1),
        outputFormat: format,
        audioEvents: [
          ExportAudioEvent(
            offset: Duration.zero,
            clip: _stereoClip([0.25, 0.25, 0.25, 0.25], format),
          ),
          ExportAudioEvent(
            offset: const Duration(milliseconds: 250),
            gain: 0.5,
            clip: _stereoClip([0.5, 0.5, 0.5, 0.5], format),
          ),
        ],
      );

      final rendered = await renderer.render(project);

      expect(
        rendered.samples,
        Float32List.fromList([
          0.25,
          0.25,
          0.5,
          0.5,
          0.25,
          0.25,
          0.0,
          0.0,
        ]),
      );
    });

    test('clips mixed samples into the valid float range', () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(milliseconds: 500),
        outputFormat: format,
        audioEvents: [
          ExportAudioEvent(
            offset: Duration.zero,
            clip: _stereoClip([0.9, -0.9], format),
          ),
          ExportAudioEvent(
            offset: Duration.zero,
            clip: _stereoClip([0.7, -0.7], format),
          ),
        ],
      );

      final rendered = await renderer.render(project);

      expect(
        rendered.samples,
        Float32List.fromList([1.0, -1.0, 0.0, 0.0]),
      );
    });

    test('ignores events that start after the export duration', () async {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(milliseconds: 500),
        outputFormat: format,
        audioEvents: [
          ExportAudioEvent(
            offset: const Duration(seconds: 2),
            clip: _stereoClip([0.5, 0.5], format),
          ),
        ],
      );

      final rendered = await renderer.render(project);

      expect(rendered.samples, Float32List.fromList([0.0, 0.0, 0.0, 0.0]));
    });

    test('throws when an event clip does not match the output format', () {
      final project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(seconds: 1),
        outputFormat: format,
        audioEvents: [
          ExportAudioEvent(
            offset: Duration.zero,
            clip: ExportAudioClip(
              samples: Float32List.fromList([0.5, 0.5]),
              sampleRate: 8,
              channelCount: 2,
            ),
          ),
        ],
      );

      expect(
        () => renderer.render(project),
        throwsArgumentError,
      );
    });
  });
}

ExportAudioClip _stereoClip(List<double> samples, ExportAudioFormat format) {
  return ExportAudioClip(
    samples: Float32List.fromList(samples),
    sampleRate: format.sampleRate,
    channelCount: format.channelCount,
  );
}
