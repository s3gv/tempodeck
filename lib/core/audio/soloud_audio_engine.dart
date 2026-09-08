import 'dart:async';

import 'package:logging/logging.dart';

import '../domain/accent_level.dart';
import '../domain/audio_cue.dart';
import '../domain/click_sound_set.dart';
import 'audio_playback_session.dart';
import 'audio_engine_config.dart';
import 'audio_cue_tone_library.dart';
import 'audio_limiter_settings.dart';
import 'click_sound_set_assets.dart';
import 'click_channel_volume_profile.dart';
import 'i_audio_engine.dart';
import 'soloud_client.dart';
import 'text_to_speech_client.dart';

class SoLoudAudioEngine implements IAudioEngine {
  SoLoudAudioEngine({
    SoLoudClient? soLoudClient,
    TextToSpeechClient? textToSpeechClient,
    AudioPlaybackSession? playbackSession,
    AudioEngineConfig? config,
  })  : _soLoudClient = soLoudClient ?? FlutterSoLoudClient(),
        _textToSpeechClient = textToSpeechClient ?? FlutterTextToSpeechClient(),
        _playbackSession = playbackSession ?? SystemAudioPlaybackSession(),
        _config = config ?? const AudioEngineConfig();

  static final Logger _logger = Logger('SoLoudAudioEngine');
  static const double _defaultMasterVolume = 1.0;
  static const String _fallbackVoiceLocale = 'en-US';

  final SoLoudClient _soLoudClient;
  final TextToSpeechClient _textToSpeechClient;
  final AudioPlaybackSession _playbackSession;
  final AudioEngineConfig _config;
  final Map<ClickSoundSet, Map<ClickSoundVariant, SoLoudSourceHandle>>
      _loadedClickSources = {};
  final Map<AudioCueType, SoLoudSourceHandle> _loadedCueSources = {};
  final Map<String, SoLoudSourceHandle> _loadedFileSources = {};
  final Map<String, Future<SoLoudSourceHandle>> _loadingFileSources = {};
  final Map<String, _PreparedLinkedAudioPlayback> _preparedLinkedAudio = {};
  final Map<String?, _ResolvedVoiceSelection> _resolvedVoiceSelections = {};
  List<TextToSpeechVoice>? _availableVoices;
  bool _isTextToSpeechReady = false;

  ClickSoundSet _activeClickSoundSet = ClickSoundSet.tock;
  ClickChannelVolumeProfile _clickChannelVolumes =
      const ClickChannelVolumeProfile();
  AudioLimiterSettings _limiterSettings = const AudioLimiterSettings();
  double _masterVolume = _defaultMasterVolume;

  @override
  bool get isInitialized => _soLoudClient.isInitialized;

  @override
  Future<void> initialize() async {
    if (_soLoudClient.isInitialized) {
      _soLoudClient.setGlobalVolume(_masterVolume);
      _soLoudClient.setLimiter(_limiterSettings);
      return;
    }

    await _playbackSession.configureForPlayback();
    await _playbackSession.activate();

    await _soLoudClient.init(
      sampleRate: _config.sampleRate,
      bufferSize: _config.bufferSize,
      channels: _config.channels,
    );
    _soLoudClient.setGlobalVolume(_masterVolume);
    _soLoudClient.setLimiter(_limiterSettings);

    for (final soundSet in ClickSoundSet.values) {
      await loadClickSoundSet(soundSet);
    }

    await _loadCueSources();
  }

  @override
  Future<void> dispose() async {
    await _textToSpeechClient.stop();

    if (_soLoudClient.isInitialized) {
      _clearLoadedSources();
      _soLoudClient.deinit();
    }

    _playbackSession.onInterruption = null;
    await _playbackSession.deactivate();
  }

  @override
  Future<void> loadClickSoundSet(ClickSoundSet set) async {
    if (!_soLoudClient.isInitialized) return;
    if (_loadedClickSources.containsKey(set)) {
      return;
    }

    final assets = ClickSoundSetAssets.forSoundSet(set);
    final loadedSources = <ClickSoundVariant, SoLoudSourceHandle>{};

    for (final variant in ClickSoundVariant.values) {
      loadedSources[variant] = await _soLoudClient.loadAsset(
        assets.assetPathFor(variant),
      );
    }

    _loadedClickSources[set] = Map.unmodifiable(loadedSources);
  }

  @override
  void selectClickSoundSet(ClickSoundSet set) {
    if (!_soLoudClient.isInitialized) return;
    if (!_loadedClickSources.containsKey(set)) {
      throw StateError('Click sound set $set is not loaded.');
    }

    _activeClickSoundSet = set;
  }

  @override
  void playClick(AccentLevel accent) {
    if (!_soLoudClient.isInitialized) return;
    if (accent == AccentLevel.mute) {
      return;
    }

    final soundSet = _loadedClickSources[_activeClickSoundSet];
    if (soundSet == null) {
      throw StateError('Click sound set $_activeClickSoundSet is not loaded.');
    }

    final variant = _variantForAccent(accent);
    final volume = _clickChannelVolumes.volumeFor(variant);
    if (volume == 0) {
      return;
    }

    final handle = soundSet[variant];
    if (handle == null) {
      throw StateError(
        'Variant $variant is not loaded for sound set $_activeClickSoundSet.',
      );
    }

    unawaited(
      _soLoudClient.play(handle, volume: volume).then(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('Failed to play click.', error, stackTrace);
        },
      ),
    );
  }

  @override
  void playSubdivisionClick() {
    if (!_soLoudClient.isInitialized) return;

    final soundSet = _loadedClickSources[_activeClickSoundSet];
    if (soundSet == null) return;

    const variant = ClickSoundVariant.subdivision;
    final volume = _clickChannelVolumes.volumeFor(variant);
    if (volume == 0) return;

    final handle = soundSet[variant];
    if (handle == null) return;

    unawaited(
      _soLoudClient.play(handle, volume: volume).then(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning(
            'Failed to play subdivision click.',
            error,
            stackTrace,
          );
        },
      ),
    );
  }

  @override
  Future<void> playCue(AudioCue cue) {
    if (!_soLoudClient.isInitialized) return Future<void>.value();
    if (cue.type == AudioCueType.voice) {
      final text = cue.voiceText;
      if (text == null || text.trim().isEmpty) {
        throw ArgumentError.value(
          cue.voiceText,
          'cue.voiceText',
          'voice cues require non-empty text',
        );
      }

      return speakCue(
        text,
        voiceIdentifier: cue.voiceIdentifier,
      );
    }

    if (cue.type == AudioCueType.customFile) {
      final filePath = cue.customFilePath;
      if (filePath == null || filePath.isEmpty) {
        throw ArgumentError.value(
          cue.customFilePath,
          'cue.customFilePath',
          'custom file cues require a file path',
        );
      }

      return playLinkedAudio(
        filePath,
        offset: Duration.zero,
        volume: _cueVolume(cue),
      );
    }

    final source = _loadedCueSources[cue.type];
    if (source == null) {
      throw UnimplementedError(
        'Cue type ${cue.type} is implemented in a later A3 PR.',
      );
    }

    return _soLoudClient.play(source, volume: _cueVolume(cue));
  }

  @override
  Future<List<TextToSpeechVoice>> getAvailableVoices() async {
    if (!isInitialized) return [];
    await _ensureTextToSpeechReady();

    final voices = await _loadAvailableVoices();
    return voices.where((v) => v.identifier != null).toList();
  }

  @override
  Future<void> speakCue(String text, {String? voiceIdentifier}) async {
    if (!_soLoudClient.isInitialized) {
      throw StateError('Audio engine is not initialized.');
    }
    if (text.trim().isEmpty) {
      throw ArgumentError.value(
        text,
        'text',
        'Voice cue text must not be empty.',
      );
    }

    await _ensureTextToSpeechReady();

    final selection = await _resolveVoiceSelection(
      voiceIdentifier: voiceIdentifier,
    );

    await _textToSpeechClient.setLanguage(selection.language);
    if (selection.voice != null) {
      await _textToSpeechClient.setVoice(selection.voice!);
    }

    await _textToSpeechClient.speak(text);
  }

  @override
  Future<void> preloadLinkedAudio(String filePath) async {
    if (!_soLoudClient.isInitialized) {
      return;
    }

    await _loadFileSource(filePath);
  }

  @override
  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {
    if (!_soLoudClient.isInitialized) {
      throw StateError('Audio engine is not initialized.');
    }

    final normalizedOffset = _normalizedOffset(offset);
    final normalizedVolume = volume.clamp(0.0, 1.0);
    final source = await _loadFileSource(filePath);
    final handleId = _preparedHandleId(filePath);

    final existingPlayback = _preparedLinkedAudio.remove(handleId);
    if (existingPlayback != null) {
      await _soLoudClient.stopSourceVoices(existingPlayback.source);
    }

    final voice = await _soLoudClient.play(
      source,
      volume: normalizedVolume,
      paused: true,
    );
    if (normalizedOffset > Duration.zero) {
      _soLoudClient.seek(voice, normalizedOffset);
    }

    _preparedLinkedAudio[handleId] = _PreparedLinkedAudioPlayback(
      source: source,
      voice: voice,
    );
    return PreparedLinkedAudioHandle(handleId);
  }

  @override
  Future<void> playPreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {
    final playback = _preparedLinkedAudio.remove(handle.id);
    if (playback == null) {
      throw StateError('Prepared linked audio handle ${handle.id} was not found.');
    }
    _soLoudClient.setPause(playback.voice, false);
  }

  @override
  Future<void> releasePreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {
    final playback = _preparedLinkedAudio.remove(handle.id);
    if (playback == null) {
      return;
    }
    await _soLoudClient.stopSourceVoices(playback.source);
  }

  @override
  Future<void> playLinkedAudio(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {
    if (!_soLoudClient.isInitialized) return;
    final normalizedOffset = _normalizedOffset(offset);
    final normalizedVolume = volume.clamp(0.0, 1.0);
    final source = await _loadFileSource(filePath);
    final voice = await _soLoudClient.play(
      source,
      volume: normalizedVolume,
      paused: normalizedOffset > Duration.zero,
    );

    if (normalizedOffset > Duration.zero) {
      _soLoudClient.seek(voice, normalizedOffset);
      _soLoudClient.setPause(voice, false);
    }
  }

  @override
  void setClickChannelVolume(ClickSoundVariant variant, double volume) {
    assert(
      volume >= 0 && volume <= 1,
      'Click channel volume must stay within 0.0–1.0.',
    );

    final clampedVolume = volume.clamp(0.0, 1.0);
    _clickChannelVolumes = _clickChannelVolumes.copyWithVolume(
      variant,
      clampedVolume,
    );
  }

  @override
  void setLimiter(AudioLimiterSettings settings) {
    _limiterSettings = settings;

    if (_soLoudClient.isInitialized) {
      _soLoudClient.setLimiter(_limiterSettings);
    }
  }

  @override
  void setMasterVolume(double volume) {
    assert(
      volume >= 0 && volume <= 1,
      'Master volume must stay within 0.0–1.0.',
    );

    _masterVolume = volume.clamp(0.0, 1.0);

    if (_soLoudClient.isInitialized) {
      _soLoudClient.setGlobalVolume(_masterVolume);
    }
  }

  @override
  Future<void> stop() async {
    if (!_soLoudClient.isInitialized) {
      return;
    }

    await _stopActivePlayback();
    await _textToSpeechClient.stop();
  }

  ClickSoundVariant _variantForAccent(AccentLevel accent) {
    return switch (accent) {
      AccentLevel.high => ClickSoundVariant.accentHigh,
      AccentLevel.normal => ClickSoundVariant.normal,
      AccentLevel.low => ClickSoundVariant.accentLow,
      AccentLevel.mute =>
        throw StateError('Muted accents should not be played.'),
    };
  }

  Future<void> _loadCueSources() async {
    for (final type in AudioCueType.values) {
      final spec = AudioCueToneLibrary.specFor(type);
      if (spec == null || _loadedCueSources.containsKey(type)) {
        continue;
      }

      _loadedCueSources[type] = await _soLoudClient.loadBytes(
        spec.assetKey,
        AudioCueToneLibrary.buildWaveFile(spec),
      );
    }
  }

  double _cueVolume(AudioCue cue) {
    final volume = cue.volumePercent / 100;
    assert(volume >= 0 && volume <= 1, 'Cue volume must stay within 0.0–1.0.');
    return volume.clamp(0.0, 1.0);
  }

  Duration _normalizedOffset(Duration offset) {
    assert(!offset.isNegative, 'Linked audio offset must be >= 0.');
    if (offset.isNegative) {
      return Duration.zero;
    }

    return offset;
  }

  Future<SoLoudSourceHandle> _loadFileSource(String filePath) async {
    final cachedSource = _loadedFileSources[filePath];
    if (cachedSource != null) {
      return cachedSource;
    }

    final pendingLoad = _loadingFileSources[filePath];
    if (pendingLoad != null) {
      return pendingLoad;
    }

    final loadFuture = _soLoudClient.loadFile(filePath).then((loadedSource) {
      _loadedFileSources[filePath] = loadedSource;
      return loadedSource;
    });
    _loadingFileSources[filePath] = loadFuture;

    try {
      return await loadFuture;
    } finally {
      final _ = _loadingFileSources.remove(filePath);
    }
  }

  /// Ensures TTS is ready by calling [awaitSpeakCompletion] once.
  ///
  /// Throws [StateError] if TTS cannot be initialized. Callers must handle the
  /// error — silent no-ops are not acceptable.
  Future<void> _ensureTextToSpeechReady() async {
    if (_isTextToSpeechReady) {
      return;
    }

    try {
      await _textToSpeechClient.awaitSpeakCompletion(true);
      _isTextToSpeechReady = true;
    } catch (error, stackTrace) {
      _logger.severe(
        'Text-to-speech initialization failed.',
        error,
        stackTrace,
      );
      throw StateError(
        'Text-to-speech is not available on this device: $error',
      );
    }
  }

  Future<List<TextToSpeechVoice>> _loadAvailableVoices() async {
    final cachedVoices = _availableVoices;
    if (cachedVoices != null) {
      return cachedVoices;
    }

    final loadedVoices = await _textToSpeechClient.getVoices();
    final voices = List<TextToSpeechVoice>.unmodifiable(loadedVoices);
    _availableVoices = voices;
    return voices;
  }

  void _clearLoadedSources() {
    _loadedClickSources.clear();
    _loadedCueSources.clear();
    _loadedFileSources.clear();
    _loadingFileSources.clear();
    _preparedLinkedAudio.clear();
    _resolvedVoiceSelections.clear();
    _availableVoices = null;
    _isTextToSpeechReady = false;
  }

  Future<void> _stopActivePlayback() async {
    for (final soundSet in _loadedClickSources.values) {
      for (final source in soundSet.values) {
        await _soLoudClient.stopSourceVoices(source);
      }
    }

    for (final source in _loadedCueSources.values) {
      await _soLoudClient.stopSourceVoices(source);
    }

    for (final source in _loadedFileSources.values) {
      await _soLoudClient.stopSourceVoices(source);
    }
    _preparedLinkedAudio.clear();
  }

  String _preparedHandleId(String filePath) => 'linked-audio::$filePath';

  Future<_ResolvedVoiceSelection> _resolveVoiceSelection({
    required String? voiceIdentifier,
  }) async {
    final cachedSelection = _resolvedVoiceSelections[voiceIdentifier];
    if (cachedSelection != null) {
      return cachedSelection;
    }

    final voices = await _loadAvailableVoices();
    final preferredVoice = _findVoiceByIdentifier(voices, voiceIdentifier);
    final fallbackVoice = _findFallbackVoice(voices);
    final resolvedSelection = preferredVoice != null
        ? _ResolvedVoiceSelection(
            language: preferredVoice.locale,
            voice: preferredVoice,
          )
        : _ResolvedVoiceSelection(
            language: fallbackVoice?.locale ?? _fallbackVoiceLocale,
            voice: fallbackVoice,
          );

    _resolvedVoiceSelections[voiceIdentifier] = resolvedSelection;
    return resolvedSelection;
  }

  TextToSpeechVoice? _findVoiceByIdentifier(
    List<TextToSpeechVoice> voices,
    String? voiceIdentifier,
  ) {
    if (voiceIdentifier == null || voiceIdentifier.isEmpty) {
      return null;
    }

    for (final voice in voices) {
      if (voice.identifier == voiceIdentifier) {
        return voice;
      }
    }

    return null;
  }

  TextToSpeechVoice? _findFallbackVoice(List<TextToSpeechVoice> voices) {
    for (final voice in voices) {
      if (_normalizedLocale(voice.locale) ==
          _normalizedLocale(_fallbackVoiceLocale)) {
        return voice;
      }
    }

    return null;
  }

  String _normalizedLocale(String locale) =>
      locale.replaceAll('_', '-').toLowerCase();
}

class _PreparedLinkedAudioPlayback {
  const _PreparedLinkedAudioPlayback({
    required this.source,
    required this.voice,
  });

  final SoLoudSourceHandle source;
  final SoLoudVoiceHandle voice;
}

class _ResolvedVoiceSelection {
  const _ResolvedVoiceSelection({
    required this.language,
    required this.voice,
  });

  final String language;
  final TextToSpeechVoice? voice;
}
