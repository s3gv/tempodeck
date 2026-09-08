import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/audio_engine_config.dart';
import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/soloud_audio_engine.dart';
import 'package:tempodeck/core/audio/soloud_client.dart';
import 'package:tempodeck/core/audio/text_to_speech_client.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_playback_session_test_support.dart';

void main() {
  group('ClickSoundSetAssets', () {
    test('maps every click sound set to four asset files', () {
      for (final soundSet in ClickSoundSet.values) {
        final assets = ClickSoundSetAssets.forSoundSet(soundSet);

        expect(assets.assetPaths, hasLength(4));
        for (final assetPath in assets.assetPaths) {
          expect(assetPath, startsWith('assets/audio/click_kits/'));
          expect(assetPath, endsWith('.wav'));
        }
      }
    });
  });

  group('AudioEngineConfig', () {
    test('uses the low-latency default SoLoud init values', () {
      const config = AudioEngineConfig();

      expect(config.sampleRate, AudioEngineConfig.defaultSampleRate);
      expect(config.sampleRate, 44100);
      expect(config.bufferSize, AudioEngineConfig.defaultBufferSize);
      expect(config.bufferSize, 512);
      expect(config.channels, AudioEngineConfig.defaultChannels);
      expect(config.channels, Channels.stereo);
    });
  });

  group('SoLoudAudioEngine', () {
    late FakeSoLoudClient client;
    late FakeTextToSpeechClient textToSpeechClient;
    late FakeAudioPlaybackSession playbackSession;
    late SoLoudAudioEngine engine;

    setUp(() {
      client = FakeSoLoudClient();
      textToSpeechClient = FakeTextToSpeechClient();
      playbackSession = FakeAudioPlaybackSession();
      engine = SoLoudAudioEngine(
        soLoudClient: client,
        textToSpeechClient: textToSpeechClient,
        playbackSession: playbackSession,
        config: const AudioEngineConfig(),
      );
    });

    test('initializes SoLoud with the configured sample rate and buffer',
        () async {
      await engine.initialize();

      expect(client.initCallCount, 1);
      expect(
        client.loadedAssetPaths,
        hasLength(ClickSoundSet.values.length * 4),
      );
      expect(client.loadedGeneratedSources, hasLength(5));
      expect(client.sampleRate, 44100);
      expect(client.bufferSize, 512);
      expect(client.channels, Channels.stereo);
      expect(client.globalVolume, 1);
      expect(client.limiterSettings, const AudioLimiterSettings());
      expect(playbackSession.configureCallCount, 1);
      expect(playbackSession.activateCallCount, 1);
      expect(textToSpeechClient.awaitSpeakCompletionCalls, isEmpty);
      expect(textToSpeechClient.getVoicesCallCount, 0);
    });

    test('reuses an initialized engine without reinitializing SoLoud',
        () async {
      client.isInitializedValue = true;

      await engine.initialize();

      expect(client.initCallCount, 0);
      expect(client.loadedAssetPaths, isEmpty);
      expect(client.globalVolume, 1);
      expect(client.limiterSettings, const AudioLimiterSettings());
      expect(playbackSession.configureCallCount, 0);
      expect(playbackSession.activateCallCount, 0);
      expect(textToSpeechClient.awaitSpeakCompletionCalls, isEmpty);
      expect(textToSpeechClient.getVoicesCallCount, 0);
    });

    test('initializes without touching text-to-speech setup', () async {
      textToSpeechClient.throwOnAwaitSpeakCompletion = true;
      textToSpeechClient.throwOnGetVoices = true;

      await engine.initialize();

      expect(client.initCallCount, 1);
      expect(playbackSession.configureCallCount, 1);
      expect(playbackSession.activateCallCount, 1);
      expect(textToSpeechClient.awaitSpeakCompletionCalls, isEmpty);
      expect(textToSpeechClient.getVoicesCallCount, 0);
    });

    test('applies a preconfigured master volume during initialization',
        () async {
      engine.setMasterVolume(0.35);

      await engine.initialize();

      expect(client.globalVolume, 0.35);
    });

    test('updates global volume immediately after initialization', () async {
      await engine.initialize();

      engine.setMasterVolume(0.6);

      expect(client.globalVolume, 0.6);
    });

    test('asserts when master volume is outside the supported range', () async {
      await engine.initialize();

      expect(() => engine.setMasterVolume(2), throwsA(isA<AssertionError>()));
      expect(() => engine.setMasterVolume(-1), throwsA(isA<AssertionError>()));
    });

    test('loads a click sound set only once', () async {
      await engine.initialize();
      final initialLoadCount = client.loadedAssetPaths.length;

      await engine.loadClickSoundSet(ClickSoundSet.tock);

      expect(client.loadedAssetPaths, hasLength(initialLoadCount));
    });

    test('plays the selected click source for the requested accent', () async {
      await engine.initialize();
      await engine.loadClickSoundSet(ClickSoundSet.hype);
      engine.selectClickSoundSet(ClickSoundSet.hype);

      engine.playClick(AccentLevel.low);

      expect(
        client.playedAssetPaths,
        ['assets/audio/click_kits/hype/hype_accent_low.wav'],
      );
      expect(client.playedVolumes, [1.0]);
    });

    test('plays generated interval and pulse cues at the requested volume',
        () async {
      await engine.initialize();

      await engine.playCue(
        const AudioCue(
          type: AudioCueType.highPulse,
          volumePercent: 40,
        ),
      );
      await engine.playCue(
        const AudioCue(
          type: AudioCueType.intervalSignal,
        ),
      );

      expect(
        client.playedAssetPaths,
        [
          'generated://cue/high_pulse.wav',
          'generated://cue/interval_signal.wav',
        ],
      );
      expect(client.playedVolumes, [0.4, 1.0]);
    });

    test('plays every generated synthetic cue type through preloaded sources',
        () async {
      await engine.initialize();

      for (final cueType in const [
        AudioCueType.intervalSignal,
        AudioCueType.maxSignal,
        AudioCueType.lowPulse,
        AudioCueType.midPulse,
        AudioCueType.highPulse,
      ]) {
        await engine.playCue(AudioCue(type: cueType));
      }

      expect(
        client.playedAssetPaths,
        [
          'generated://cue/interval_signal.wav',
          'generated://cue/max_signal.wav',
          'generated://cue/low_pulse.wav',
          'generated://cue/mid_pulse.wav',
          'generated://cue/high_pulse.wav',
        ],
      );
    });

    test('plays custom file cues via linked audio playback', () async {
      await engine.initialize();

      await engine.playCue(
        const AudioCue(
          type: AudioCueType.customFile,
          customFilePath: '/tmp/cue.wav',
          volumePercent: 25,
        ),
      );

      expect(client.loadedFilePaths, ['/tmp/cue.wav']);
      expect(
        client.playedAssetPaths,
        ['/tmp/cue.wav'],
      );
      expect(client.playedVolumes, [0.25]);
    });

    test('plays linked audio from the requested offset and volume', () async {
      await engine.initialize();

      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: const Duration(seconds: 7),
        volume: 0.6,
      );

      expect(client.loadedFilePaths, ['/tmp/backing.wav']);
      expect(client.playedAssetPaths, ['/tmp/backing.wav']);
      expect(client.playedVolumes, [0.6]);
      expect(client.seekOffsets, [const Duration(seconds: 7)]);
      expect(client.pauseStates, [false]);
    });

    test('preloads linked audio sources before playback', () async {
      await engine.initialize();

      await engine.preloadLinkedAudio('/tmp/backing.wav');

      expect(client.loadedFilePaths, ['/tmp/backing.wav']);
      expect(client.playedAssetPaths, isEmpty);
    });

    test('prepares linked audio paused at the requested offset and resumes it',
        () async {
      await engine.initialize();

      final handle = await engine.prepareLinkedAudioPlayback(
        '/tmp/backing.wav',
        offset: const Duration(milliseconds: 2003),
        volume: 0.6,
      );

      expect(client.loadedFilePaths, ['/tmp/backing.wav']);
      expect(client.playedAssetPaths, ['/tmp/backing.wav']);
      expect(client.playedVolumes, [0.6]);
      expect(client.playedPausedStates, [true]);
      expect(client.seekOffsets, [const Duration(milliseconds: 2003)]);

      await engine.playPreparedLinkedAudio(handle);

      expect(client.pauseStates, [false]);
    });

    test('reuses the same file source when preload and play overlap', () async {
      final delayedClient = DelayedFileLoadSoLoudClient();
      client = delayedClient;
      engine = SoLoudAudioEngine(
        soLoudClient: client,
        textToSpeechClient: textToSpeechClient,
        playbackSession: playbackSession,
        config: const AudioEngineConfig(),
      );
      await engine.initialize();

      final preloadFuture = engine.preloadLinkedAudio('/tmp/backing.wav');
      final playFuture = engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: Duration.zero,
        volume: 1,
      );

      expect(client.loadedFilePaths, ['/tmp/backing.wav']);

      delayedClient.completePendingFileLoad();
      await preloadFuture;
      await playFuture;
      await engine.stop();

      expect(
        client.loadedFilePaths.where((path) => path == '/tmp/backing.wav'),
        hasLength(1),
      );
      expect(client.stoppedAssetPaths, contains('/tmp/backing.wav'));
    });

    test('reuses cached linked audio sources across repeated playback',
        () async {
      await engine.initialize();

      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: Duration.zero,
        volume: 1,
      );
      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: Duration.zero,
        volume: 0.5,
      );

      expect(client.loadedFilePaths, ['/tmp/backing.wav']);
      expect(client.playedVolumes, [1.0, 0.5]);
    });

    test('plays voice cues with the requested voice identifier', () async {
      await engine.initialize();

      await engine.playCue(
        const AudioCue(
          type: AudioCueType.voice,
          voiceText: 'Go',
          voiceIdentifier: 'custom-voice',
        ),
      );

      expect(textToSpeechClient.spokenTexts, ['Go']);
      expect(textToSpeechClient.setLanguageCalls, ['de-DE']);
      expect(textToSpeechClient.setVoiceCalls, [
        const TextToSpeechVoice(
          name: 'German Voice',
          locale: 'de-DE',
          identifier: 'custom-voice',
        ),
      ]);
    });

    test('uses US English when the requested voice identifier is not available', () async {
      await engine.initialize();

      await engine.speakCue(
        'Ready',
        voiceIdentifier: 'missing-voice',
      );

      expect(textToSpeechClient.setLanguageCalls, ['en-US']);
      expect(textToSpeechClient.setVoiceCalls, [
        const TextToSpeechVoice(
          name: 'English Voice',
          locale: 'en-US',
          identifier: 'english-voice',
        ),
      ]);
      expect(textToSpeechClient.spokenTexts, ['Ready']);
    });

    test('caches resolved voice selections across different texts', () async {
      await engine.initialize();

      await engine.speakCue(
        'Ready',
        voiceIdentifier: 'custom-voice',
      );
      await engine.speakCue(
        'Set',
        voiceIdentifier: 'custom-voice',
      );

      expect(textToSpeechClient.getVoicesCallCount, 1);
      expect(textToSpeechClient.setVoiceCalls, hasLength(2));
      expect(textToSpeechClient.spokenTexts, ['Ready', 'Set']);
      expect(textToSpeechClient.awaitSpeakCompletionCalls, [true]);
    });

    test('does not re-run text-to-speech readiness after first success',
        () async {
      await engine.initialize();

      await engine.speakCue(
        'Ready',
        voiceIdentifier: 'custom-voice',
      );

      expect(textToSpeechClient.awaitSpeakCompletionCalls, [true]);
    });

    test('throws when text-to-speech readiness fails on speakCue', () async {
      await engine.initialize();
      textToSpeechClient.throwOnAwaitSpeakCompletion = true;

      expect(
        () => engine.speakCue(
          'Ready',
          voiceIdentifier: 'custom-voice',
        ),
        throwsStateError,
      );
    });

    test('throws when a voice cue has no text', () async {
      await engine.initialize();

      expect(
        () => engine.playCue(
          const AudioCue(type: AudioCueType.voice),
        ),
        throwsArgumentError,
      );
    });

    test('keeps the default click set after preloading all sound sets',
        () async {
      await engine.initialize();

      engine.playClick(AccentLevel.normal);

      expect(
        client.playedAssetPaths,
        ['assets/audio/click_kits/tock/tock_normal.wav'],
      );
    });

    test(
        'ignores click sound set selection before engine initialization',
        () {
      engine.selectClickSoundSet(ClickSoundSet.hype);
    });

    test('applies click channel volume to subsequent playback', () async {
      await engine.initialize();
      engine.setClickChannelVolume(ClickSoundVariant.accentHigh, 0.35);

      engine.playClick(AccentLevel.high);

      expect(client.playedVolumes, [0.35]);
    });

    test('does not play anything for mute accents', () async {
      await engine.initialize();

      engine.playClick(AccentLevel.mute);

      expect(client.playedAssetPaths, isEmpty);
    });

    test('updates limiter settings immediately after initialization', () async {
      await engine.initialize();

      const limiter = AudioLimiterSettings(
        wet: 0.8,
        threshold: -8,
        outputCeiling: -2,
        kneeWidth: 4,
        releaseTimeMs: 150,
        attackTimeMs: 2,
      );
      engine.setLimiter(limiter);

      expect(client.limiterSettings, limiter);
    });

    test('asserts when click channel volume is outside the supported range',
        () async {
      await engine.initialize();

      expect(
        () => engine.setClickChannelVolume(ClickSoundVariant.normal, 2),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => engine.setClickChannelVolume(ClickSoundVariant.subdivision, -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('stub path can select loaded click sound sets without throwing',
        () async {
      await engine.initialize();

      expect(
        () => engine.selectClickSoundSet(ClickSoundSet.mightyKit),
        returnsNormally,
      );
    });

    test('does not try to deinit a client that was never initialized',
        () async {
      await engine.dispose();

      expect(client.deinitCallCount, 0);
      expect(playbackSession.deactivateCallCount, 1);
    });

    test('deinitializes the client when disposing an active engine', () async {
      await engine.initialize();

      await engine.dispose();

      expect(client.deinitCallCount, 1);
      expect(playbackSession.deactivateCallCount, 1);
    });

    test('clears loaded sources when the engine is reinitialized after dispose',
        () async {
      await engine.initialize();
      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: Duration.zero,
        volume: 1,
      );
      final initialAssetLoadCount = client.loadedAssetPaths.length;
      final initialGeneratedLoadCount = client.loadedGeneratedSources.length;
      final initialFileLoadCount = client.loadedFilePaths.length;

      await engine.dispose();
      await engine.initialize();
      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: Duration.zero,
        volume: 1,
      );

      expect(client.loadedAssetPaths, hasLength(initialAssetLoadCount * 2));
      expect(
        client.loadedGeneratedSources,
        hasLength(initialGeneratedLoadCount * 2),
      );
      expect(client.loadedFilePaths, hasLength(initialFileLoadCount * 2));
    });

    test('stop stops active playback and text to speech', () async {
      await engine.initialize();
      engine.playClick(AccentLevel.high);
      await engine.playCue(const AudioCue(type: AudioCueType.intervalSignal));
      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: Duration.zero,
        volume: 1,
      );

      await engine.stop();

      expect(
        client.stoppedAssetPaths,
        containsAll([
          'assets/audio/click_kits/tock/tock_accent_high.wav',
          'generated://cue/interval_signal.wav',
          '/tmp/backing.wav',
        ]),
      );
      expect(textToSpeechClient.stopCallCount, 1);
    });

    test('stop allows linked audio playback to start again with a new offset',
        () async {
      await engine.initialize();

      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: const Duration(milliseconds: 750),
        volume: 1,
      );
      await engine.stop();

      await engine.playLinkedAudio(
        '/tmp/backing.wav',
        offset: const Duration(milliseconds: 2003),
        volume: 0.8,
      );

      expect(
        client.stoppedAssetPaths,
        contains('/tmp/backing.wav'),
      );
      expect(
        client.playedAssetPaths.where((path) => path == '/tmp/backing.wav'),
        hasLength(2),
      );
      expect(
        client.seekOffsets,
        [
          const Duration(milliseconds: 750),
          const Duration(milliseconds: 2003),
        ],
      );
      expect(client.playedVolumes, [1.0, 0.8]);
    });
  });
}

class FakeSoLoudClient implements SoLoudClient {
  int initCallCount = 0;
  int deinitCallCount = 0;
  int? sampleRate;
  int? bufferSize;
  Channels? channels;
  double? globalVolume;
  AudioLimiterSettings? limiterSettings;
  bool isInitializedValue = false;
  final List<String> loadedAssetPaths = [];
  final List<String> loadedGeneratedSources = [];
  final List<String> loadedFilePaths = [];
  final List<String> playedAssetPaths = [];
  final List<double> playedVolumes = [];
  final List<bool> playedPausedStates = [];
  final List<Duration> seekOffsets = [];
  final List<bool> pauseStates = [];
  final List<String> stoppedAssetPaths = [];
  final Map<SoLoudSourceHandle, String> assetPathsByHandle = {};
  int _nextVoiceHandle = 1;

  @override
  bool get isInitialized => isInitializedValue;

  @override
  void deinit() {
    deinitCallCount++;
    isInitializedValue = false;
  }

  @override
  Future<void> init({
    required int sampleRate,
    required int bufferSize,
    required Channels channels,
  }) async {
    initCallCount++;
    this.sampleRate = sampleRate;
    this.bufferSize = bufferSize;
    this.channels = channels;
    isInitializedValue = true;
  }

  @override
  Future<SoLoudSourceHandle> loadAsset(String assetPath) async {
    loadedAssetPaths.add(assetPath);
    final handle = SoLoudSourceHandle.forTesting();
    assetPathsByHandle[handle] = assetPath;
    return handle;
  }

  @override
  Future<SoLoudSourceHandle> loadBytes(String assetKey, Uint8List bytes) async {
    loadedGeneratedSources.add(assetKey);
    final handle = SoLoudSourceHandle.forTesting();
    assetPathsByHandle[handle] = assetKey;
    return handle;
  }

  @override
  Future<SoLoudSourceHandle> loadFile(String filePath) async {
    loadedFilePaths.add(filePath);
    final handle = SoLoudSourceHandle.forTesting();
    assetPathsByHandle[handle] = filePath;
    return handle;
  }

  @override
  Future<SoLoudVoiceHandle> play(
    SoLoudSourceHandle source, {
    required double volume,
    bool paused = false,
  }) async {
    playedAssetPaths.add(assetPathsByHandle[source]!);
    playedVolumes.add(volume);
    playedPausedStates.add(paused);
    return SoLoudVoiceHandle(_nextVoiceHandle++);
  }

  @override
  Future<void> stopSourceVoices(SoLoudSourceHandle source) async {
    final path = assetPathsByHandle[source];
    assert(path != null, 'stopSourceVoices called for unregistered source');
    stoppedAssetPaths.add(path!);
  }

  @override
  void seek(SoLoudVoiceHandle voice, Duration offset) {
    seekOffsets.add(offset);
  }

  @override
  void setPause(SoLoudVoiceHandle voice, bool pause) {
    pauseStates.add(pause);
  }

  @override
  void setGlobalVolume(double volume) {
    globalVolume = volume;
  }

  @override
  void setLimiter(AudioLimiterSettings settings) {
    limiterSettings = settings;
  }

  @override
  List<PlaybackDevice> listPlaybackDevices() => const [];

  @override
  Future<void> disposeSource(SoLoudSourceHandle source) async {}

  @override
  Duration getLength(SoLoudSourceHandle source) => Duration.zero;

  @override
  void changeDevice({PlaybackDevice? newDevice}) {}

  @override
  Future<Float32List> readSamplesFromFile(
    String filePath,
    int numSamplesNeeded, {
    double startTime = 0,
    double endTime = -1,
    bool average = false,
  }) async =>
      Float32List(numSamplesNeeded);

  @override
  Future<Float32List> readSamplesFromMem(
    Uint8List buffer,
    int numSamplesNeeded, {
    double startTime = 0,
    double endTime = -1,
    bool average = false,
  }) async =>
      Float32List(numSamplesNeeded);
}

class DelayedFileLoadSoLoudClient extends FakeSoLoudClient {
  Completer<SoLoudSourceHandle>? _pendingFileLoadCompleter;

  @override
  Future<SoLoudSourceHandle> loadFile(String filePath) {
    loadedFilePaths.add(filePath);
    final handle = SoLoudSourceHandle.forTesting();
    assetPathsByHandle[handle] = filePath;
    final completer = Completer<SoLoudSourceHandle>();
    _pendingFileLoadCompleter = completer;
    return completer.future;
  }

  void completePendingFileLoad() {
    final completer = _pendingFileLoadCompleter;
    if (completer == null) {
      return;
    }

    final path = loadedFilePaths.last;
    final handle = assetPathsByHandle.entries
        .firstWhere((entry) => entry.value == path)
        .key;
    completer.complete(handle);
    _pendingFileLoadCompleter = null;
  }
}

class FakeTextToSpeechClient implements TextToSpeechClient {
  final List<bool> awaitSpeakCompletionCalls = [];
  int getVoicesCallCount = 0;
  int stopCallCount = 0;
  bool throwOnAwaitSpeakCompletion = false;
  bool throwOnGetVoices = false;
  final List<String> setLanguageCalls = [];
  final List<TextToSpeechVoice> setVoiceCalls = [];
  final List<String> spokenTexts = [];
  final List<TextToSpeechVoice> voices = const [
    TextToSpeechVoice(
      name: 'English Voice',
      locale: 'en-US',
      identifier: 'english-voice',
    ),
    TextToSpeechVoice(
      name: 'German Voice',
      locale: 'de-DE',
      identifier: 'custom-voice',
    ),
  ];

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    awaitSpeakCompletionCalls.add(awaitCompletion);
    if (throwOnAwaitSpeakCompletion) {
      throw StateError('awaitSpeakCompletion failed');
    }
  }

  @override
  Future<List<TextToSpeechVoice>> getVoices() async {
    getVoicesCallCount += 1;
    if (throwOnGetVoices) {
      throw StateError('getVoices failed');
    }
    return voices;
  }

  @override
  Future<void> setLanguage(String language) async {
    setLanguageCalls.add(language);
  }

  @override
  Future<void> setVoice(TextToSpeechVoice voice) async {
    setVoiceCalls.add(voice);
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }
}
