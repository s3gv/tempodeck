import 'package:flutter_soloud/flutter_soloud.dart';

class AudioEngineConfig {
  const AudioEngineConfig({
    this.sampleRate = defaultSampleRate,
    this.bufferSize = defaultBufferSize,
    this.channels = defaultChannels,
  });

  static const int defaultSampleRate = 44100;

  // 512 frames keeps latency low while staying well clear of underruns on
  // desktop and mobile hardware.
  static const int defaultBufferSize = 512;

  static const Channels defaultChannels = Channels.stereo;

  final int sampleRate;
  final int bufferSize;
  final Channels channels;
}
