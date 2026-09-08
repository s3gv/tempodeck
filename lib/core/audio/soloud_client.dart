import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_limiter_settings.dart';

class SoLoudSourceHandle {
  /// Creates a handle wrapping a real [AudioSource] from flutter_soloud.
  const SoLoudSourceHandle(AudioSource source) : _source = source;

  /// Creates a unique handle for testing without requiring a real [AudioSource].
  ///
  /// Each call creates a distinct instance (not const) so handles can be
  /// used as unique identity keys in test maps.
  // ignore: prefer_const_constructors_in_immutables
  SoLoudSourceHandle.forTesting() : _source = null;

  final AudioSource? _source;

  /// Returns the underlying [AudioSource].
  ///
  /// Throws [StateError] if this handle was created via [forTesting].
  AudioSource get audioSource {
    final source = _source;
    if (source == null) {
      throw StateError(
        'SoLoudSourceHandle.audioSource called on a test-only handle',
      );
    }
    return source;
  }
}

class SoLoudVoiceHandle {
  const SoLoudVoiceHandle(this._id);

  final int _id;
}

abstract class SoLoudClient {
  bool get isInitialized;

  Future<void> init({
    required int sampleRate,
    required int bufferSize,
    required Channels channels,
  });

  Future<SoLoudSourceHandle> loadAsset(String assetPath);
  Future<SoLoudSourceHandle> loadBytes(String assetKey, Uint8List bytes);
  Future<SoLoudSourceHandle> loadFile(String filePath);
  Future<SoLoudVoiceHandle> play(
    SoLoudSourceHandle source, {
    required double volume,
    bool paused = false,
  });
  Future<void> stopSourceVoices(SoLoudSourceHandle source);
  Future<void> disposeSource(SoLoudSourceHandle source);
  Duration getLength(SoLoudSourceHandle source);
  void seek(SoLoudVoiceHandle voice, Duration offset);
  void setPause(SoLoudVoiceHandle voice, bool pause);

  void deinit();

  void setLimiter(AudioLimiterSettings settings);
  void setGlobalVolume(double volume);

  /// Returns all available playback devices.
  List<PlaybackDevice> listPlaybackDevices();

  /// Switches the audio output to the given device, or system default if null.
  void changeDevice({PlaybackDevice? newDevice});

  /// Reads equally-spaced audio samples from a file for waveform visualization.
  Future<Float32List> readSamplesFromFile(
    String filePath,
    int numSamplesNeeded, {
    double startTime = 0,
    double endTime = -1,
    bool average = false,
  });

  /// Reads equally-spaced audio samples from in-memory bytes.
  /// Use this instead of [readSamplesFromFile] when the file path may not be
  /// accessible (e.g. macOS sandbox after app restart).
  Future<Float32List> readSamplesFromMem(
    Uint8List buffer,
    int numSamplesNeeded, {
    double startTime = 0,
    double endTime = -1,
    bool average = false,
  });
}

class FlutterSoLoudClient implements SoLoudClient {
  FlutterSoLoudClient({SoLoud? soLoud}) : _soLoud = soLoud ?? SoLoud.instance;

  final SoLoud _soLoud;

  @override
  bool get isInitialized => _soLoud.isInitialized;

  @override
  Future<void> init({
    required int sampleRate,
    required int bufferSize,
    required Channels channels,
  }) {
    return _soLoud.init(
      sampleRate: sampleRate,
      bufferSize: bufferSize,
      channels: channels,
    );
  }

  @override
  Future<SoLoudSourceHandle> loadAsset(String assetPath) async {
    final audioSource = await _soLoud.loadAsset(assetPath);
    return SoLoudSourceHandle(audioSource);
  }

  @override
  Future<SoLoudSourceHandle> loadBytes(String assetKey, Uint8List bytes) async {
    final audioSource = await _soLoud.loadMem(assetKey, bytes);
    return SoLoudSourceHandle(audioSource);
  }

  @override
  Future<SoLoudSourceHandle> loadFile(String filePath) async {
    final audioSource = await _soLoud.loadFile(filePath);
    return SoLoudSourceHandle(audioSource);
  }

  @override
  Future<SoLoudVoiceHandle> play(
    SoLoudSourceHandle source, {
    required double volume,
    bool paused = false,
  }) async {
    final handle = await _soLoud.play(
      source.audioSource,
      volume: volume,
      paused: paused,
    );
    return SoLoudVoiceHandle(handle.id);
  }

  @override
  Future<void> stopSourceVoices(SoLoudSourceHandle source) async {
    final audioSource = source.audioSource;
    final activeHandles = audioSource.handles.toList(growable: false);

    for (final handle in activeHandles) {
      await _soLoud.stop(handle);
    }
  }

  @override
  Future<void> disposeSource(SoLoudSourceHandle source) async {
    await _soLoud.disposeSource(source.audioSource);
  }

  @override
  Duration getLength(SoLoudSourceHandle source) {
    return _soLoud.getLength(source.audioSource);
  }

  @override
  void seek(SoLoudVoiceHandle voice, Duration offset) =>
      _soLoud.seek(SoundHandle(voice._id), offset);

  @override
  void setPause(SoLoudVoiceHandle voice, bool pause) =>
      _soLoud.setPause(SoundHandle(voice._id), pause);

  @override
  void deinit() => _soLoud.deinit();

  @override
  void setLimiter(AudioLimiterSettings settings) {
    // ignore: experimental_member_use
    final limiter = _soLoud.filters.limiterFilter;
    if (!limiter.isActive) {
      limiter.activate();
    }

    limiter.wet.value = settings.wet;
    limiter.threshold.value = settings.threshold;
    limiter.outputCeiling.value = settings.outputCeiling;
    limiter.kneeWidth.value = settings.kneeWidth;
    limiter.releaseTime.value = settings.releaseTimeMs;
    limiter.attackTime.value = settings.attackTimeMs;
  }

  @override
  void setGlobalVolume(double volume) => _soLoud.setGlobalVolume(volume);

  @override
  List<PlaybackDevice> listPlaybackDevices() =>
      _soLoud.listPlaybackDevices();

  @override
  void changeDevice({PlaybackDevice? newDevice}) =>
      _soLoud.changeDevice(newDevice: newDevice);

  @override
  Future<Float32List> readSamplesFromFile(
    String filePath,
    int numSamplesNeeded, {
    double startTime = 0,
    double endTime = -1,
    bool average = false,
  }) =>
      // ignore: experimental_member_use
      _soLoud.readSamplesFromFile(
        filePath,
        numSamplesNeeded,
        startTime: startTime,
        endTime: endTime,
        average: average,
      );

  @override
  Future<Float32List> readSamplesFromMem(
    Uint8List buffer,
    int numSamplesNeeded, {
    double startTime = 0,
    double endTime = -1,
    bool average = false,
  }) =>
      // ignore: experimental_member_use
      _soLoud.readSamplesFromMem(
        buffer,
        numSamplesNeeded,
        startTime: startTime,
        endTime: endTime,
        average: average,
      );
}
