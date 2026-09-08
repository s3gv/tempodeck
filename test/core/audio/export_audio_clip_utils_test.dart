import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/export_audio_clip_utils.dart';
import 'package:tempodeck/core/audio/export_engine.dart';

void main() {
  test('ensureStereo converts mono clip to stereo', () {
    final monoSamples = Float32List.fromList([0.1, 0.2, 0.3]);
    final monoClip = ExportAudioClip(
      samples: monoSamples,
      sampleRate: 44100,
      channelCount: 1,
    );

    final stereoClip = ensureStereo(monoClip);

    expect(stereoClip.channelCount, 2);
    expect(stereoClip.sampleRate, 44100);
    expect(stereoClip.samples.length, 6);
    // L, R, L, R, L, R
    expect(stereoClip.samples[0], closeTo(0.1, 0.001));
    expect(stereoClip.samples[1], closeTo(0.1, 0.001));
    expect(stereoClip.samples[2], closeTo(0.2, 0.001));
    expect(stereoClip.samples[3], closeTo(0.2, 0.001));
    expect(stereoClip.samples[4], closeTo(0.3, 0.001));
    expect(stereoClip.samples[5], closeTo(0.3, 0.001));
  });

  test('ensureStereo returns stereo clip unchanged', () {
    final stereoSamples = Float32List.fromList([0.1, 0.2, 0.3, 0.4]);
    final stereoClip = ExportAudioClip(
      samples: stereoSamples,
      sampleRate: 44100,
      channelCount: 2,
    );

    final result = ensureStereo(stereoClip);

    expect(identical(result, stereoClip), isTrue);
  });

  test('ensureStereo throws for unsupported channel count', () {
    final clip = ExportAudioClip(
      samples: Float32List(6),
      sampleRate: 44100,
      channelCount: 3,
    );

    expect(() => ensureStereo(clip), throwsArgumentError);
  });
}
