import '../domain/accent_level.dart';
import '../domain/audio_cue.dart';
import '../domain/click_sound_set.dart';
import 'audio_limiter_settings.dart';
import 'click_sound_set_assets.dart';
import 'text_to_speech_client.dart';

class PreparedLinkedAudioHandle {
  const PreparedLinkedAudioHandle(this.id);

  final String id;
}

abstract class IAudioEngine {
  bool get isInitialized;
  Future<void> initialize();
  Future<void> dispose();

  /// Load a click sound set into memory
  Future<void> loadClickSoundSet(ClickSoundSet set);
  void selectClickSoundSet(ClickSoundSet set);

  /// Play a click at the given accent level
  void playClick(AccentLevel accent);

  /// Play a subdivision click using the dedicated subdivision sound variant.
  void playSubdivisionClick();

  /// Play an audio cue (interval signal, pulse, custom file)
  Future<void> playCue(AudioCue cue);

  /// Returns available text-to-speech voices with metadata for UI display.
  Future<List<TextToSpeechVoice>> getAvailableVoices();

  /// Speak text via TTS
  Future<void> speakCue(String text, {String? voiceIdentifier});

  /// Play a linked audio file at the given offset
  Future<void> preloadLinkedAudio(String filePath);

  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  });

  Future<void> playPreparedLinkedAudio(PreparedLinkedAudioHandle handle);

  Future<void> releasePreparedLinkedAudio(PreparedLinkedAudioHandle handle);

  /// Play a linked audio file at the given offset
  Future<void> playLinkedAudio(
    String filePath, {
    required Duration offset,
    required double volume,
  });

  void setClickChannelVolume(ClickSoundVariant variant, double volume);
  void setLimiter(AudioLimiterSettings settings);
  void setMasterVolume(double volume); // 0.0 – 1.0
  Future<void> stop();
}
