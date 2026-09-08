import 'dart:async';

import '../../core/audio/i_audio_engine.dart';
import '../../core/audio/metronome_click_engine.dart';
import '../../core/domain/accent_level.dart';
import '../../core/domain/click_sound_set.dart';
import '../../core/domain/subdivision.dart';

class LiveMetronomeTransportConfig {
  const LiveMetronomeTransportConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.accentPattern,
    required this.clickSoundSet,
    required this.masterVolumePercent,
  });

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final List<AccentLevel> accentPattern;
  final ClickSoundSet clickSoundSet;
  final int masterVolumePercent;
}

abstract class LiveMetronomeTransport {
  bool get isRunning;

  Future<void> start(
    LiveMetronomeTransportConfig config, {
    required void Function(MetronomeBeatTick tick) onTick,
    List<MetronomeClickEngineConfig>? beatmapSequence,
  });

  void stop();
  Future<void> stopAllAudio();
}

class AudioEngineLiveMetronomeTransport implements LiveMetronomeTransport {
  static const int _maximumMasterVolumePercent = 100;

  AudioEngineLiveMetronomeTransport({
    required IAudioEngine audioEngine,
    MetronomeClickEngine? clickEngine,
  }) : _audioEngine = audioEngine,
       _clickEngine =
           clickEngine ??
           MetronomeClickEngine(
             output: _AudioEngineMetronomeClickOutput(audioEngine),
           );

  final IAudioEngine _audioEngine;
  final MetronomeClickEngine _clickEngine;

  bool _isInitialized = false;

  @override
  bool get isRunning => _clickEngine.isRunning;

  @override
  Future<void> start(
    LiveMetronomeTransportConfig config, {
    required void Function(MetronomeBeatTick tick) onTick,
    List<MetronomeClickEngineConfig>? beatmapSequence,
  }) async {
    if (isRunning) {
      throw StateError('Live metronome transport is already running.');
    }

    if (!_isInitialized) {
      await _audioEngine.initialize();
      _isInitialized = true;
    }

    if (!_audioEngine.isInitialized) {
      throw StateError('Audio engine is not available. Cannot start playback.');
    }

    await _audioEngine.loadClickSoundSet(config.clickSoundSet);
    _audioEngine.selectClickSoundSet(config.clickSoundSet);
    _audioEngine.setMasterVolume(
      config.masterVolumePercent / _maximumMasterVolumePercent,
    );

    _clickEngine.start(
      MetronomeClickEngineConfig(
        bpm: config.bpm,
        beatsPerBar: config.beatsPerBar,
        beatUnit: config.beatUnit,
        subdivision: config.subdivision,
        accentPattern: config.accentPattern,
      ),
      onBeat: onTick,
      configSequence: beatmapSequence,
    );
  }

  @override
  void stop() {
    if (!isRunning) {
      return;
    }

    _clickEngine.stop();
  }

  @override
  Future<void> stopAllAudio() async {
    stop();
    await _audioEngine.stop();
  }
}

class _AudioEngineMetronomeClickOutput implements MetronomeClickOutput {
  const _AudioEngineMetronomeClickOutput(this._audioEngine);

  final IAudioEngine _audioEngine;

  @override
  void playHighBeat() {
    _audioEngine.playClick(AccentLevel.high);
  }

  @override
  void playLowBeat() {
    _audioEngine.playClick(AccentLevel.low);
  }

  @override
  void playNormalBeat() {
    _audioEngine.playClick(AccentLevel.normal);
  }

  @override
  void playSubdivisionPulse() {
    _audioEngine.playSubdivisionClick();
  }
}
