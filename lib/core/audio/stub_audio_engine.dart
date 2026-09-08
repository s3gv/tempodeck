import '../domain/accent_level.dart';
import '../domain/audio_cue.dart';
import '../domain/click_sound_set.dart';
import 'audio_limiter_settings.dart';
import 'click_sound_set_assets.dart';
import 'i_audio_engine.dart';
import 'text_to_speech_client.dart';

class StubAudioEngine implements IAudioEngine {
  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> loadClickSoundSet(ClickSoundSet set) async {}

  @override
  void selectClickSoundSet(ClickSoundSet set) {}

  @override
  void playClick(AccentLevel accent) {}

  @override
  void playSubdivisionClick() {}

  @override
  Future<void> playCue(AudioCue cue) async {}

  @override
  Future<List<TextToSpeechVoice>> getAvailableVoices() async => [];

  @override
  Future<void> speakCue(String text, {String? voiceIdentifier}) async {}

  @override
  Future<void> preloadLinkedAudio(String filePath) async {}

  @override
  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async => const PreparedLinkedAudioHandle('stub');

  @override
  Future<void> playPreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {}

  @override
  Future<void> releasePreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {}

  @override
  Future<void> playLinkedAudio(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {}

  @override
  void setClickChannelVolume(ClickSoundVariant variant, double volume) {}

  @override
  void setLimiter(AudioLimiterSettings settings) {}

  @override
  void setMasterVolume(double volume) {}

  @override
  Future<void> stop() async {}
}
