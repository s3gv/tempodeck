import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/audio_cue.dart';
import 'wave_file_encoder.dart';

class AudioCueToneSpec {
  const AudioCueToneSpec({
    required this.frequencyHz,
    required this.duration,
    required this.assetKey,
  });

  final double frequencyHz;
  final Duration duration;
  final String assetKey;
}

final class AudioCueToneLibrary {
  static const int sampleRate = 44100;
  static const int _channels = 1;
  static const double _amplitude = 0.35;
  static const Duration _defaultDuration = Duration(milliseconds: 120);
  static const Duration _emphasisDuration = Duration(milliseconds: 180);
  static const double _lowFrequencyHz = 450;
  static const double _midFrequencyHz = 800;
  static const double _highFrequencyHz = 1000;
  static const WaveFileEncoder _waveFileEncoder = WaveFileEncoder();

  static const Map<AudioCueType, AudioCueToneSpec> _specsByType = {
    AudioCueType.intervalSignal: AudioCueToneSpec(
      frequencyHz: _midFrequencyHz,
      duration: _emphasisDuration,
      assetKey: 'generated://cue/interval_signal.wav',
    ),
    AudioCueType.maxSignal: AudioCueToneSpec(
      frequencyHz: _highFrequencyHz,
      duration: _emphasisDuration,
      assetKey: 'generated://cue/max_signal.wav',
    ),
    AudioCueType.lowPulse: AudioCueToneSpec(
      frequencyHz: _lowFrequencyHz,
      duration: _defaultDuration,
      assetKey: 'generated://cue/low_pulse.wav',
    ),
    AudioCueType.midPulse: AudioCueToneSpec(
      frequencyHz: _midFrequencyHz,
      duration: _defaultDuration,
      assetKey: 'generated://cue/mid_pulse.wav',
    ),
    AudioCueType.highPulse: AudioCueToneSpec(
      frequencyHz: _highFrequencyHz,
      duration: _defaultDuration,
      assetKey: 'generated://cue/high_pulse.wav',
    ),
  };

  static AudioCueToneSpec? specFor(AudioCueType type) => _specsByType[type];

  static Uint8List buildWaveFile(AudioCueToneSpec spec) {
    final sampleCount = (sampleRate * spec.duration.inMicroseconds) ~/
        Duration.microsecondsPerSecond;
    final samples = Float32List(sampleCount);

    final fadeSampleCount = math.max(1, sampleCount ~/ 20);
    for (var index = 0; index < sampleCount; index += 1) {
      final progressSeconds = index / sampleRate;
      final envelope = _envelope(index, sampleCount, fadeSampleCount);
      final sample = math.sin(2 * math.pi * spec.frequencyHz * progressSeconds);
      samples[index] = sample * _amplitude * envelope;
    }

    return _waveFileEncoder.encode(
      samples: samples,
      sampleRate: sampleRate,
      channelCount: _channels,
    );
  }

  static double _envelope(int index, int sampleCount, int fadeSampleCount) {
    final fadeIn = index < fadeSampleCount ? index / fadeSampleCount : 1.0;
    final fadeOutStart = sampleCount - fadeSampleCount;
    final fadeOut =
        index >= fadeOutStart ? (sampleCount - index) / fadeSampleCount : 1.0;
    return math.min(fadeIn, fadeOut).clamp(0.0, 1.0);
  }
}
