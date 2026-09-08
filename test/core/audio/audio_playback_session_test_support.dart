import 'package:tempodeck/core/audio/audio_playback_session.dart';

class FakeAudioPlaybackSession implements AudioPlaybackSession {
  int configureCallCount = 0;
  int activateCallCount = 0;
  int deactivateCallCount = 0;
  AudioInterruptionCallback? _onInterruption;

  @override
  set onInterruption(AudioInterruptionCallback? callback) {
    _onInterruption = callback;
  }

  /// Simulates an audio interruption event for testing.
  void simulateInterruption(bool began, AudioInterruptionReason reason) {
    _onInterruption?.call(began, reason);
  }

  @override
  Future<void> activate() async {
    activateCallCount += 1;
  }

  @override
  Future<void> configureForPlayback() async {
    configureCallCount += 1;
  }

  @override
  Future<void> deactivate() async {
    deactivateCallCount += 1;
  }
}
