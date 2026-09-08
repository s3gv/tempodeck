import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';

/// Reason the audio session was interrupted.
enum AudioInterruptionReason {
  /// Another app took audio focus (phone call, Siri, etc.).
  externalInterruption,

  /// Android: audio focus lost transiently (navigation prompt, notification).
  transientFocusLoss,

  /// Android: audio focus lost and the app should duck (lower volume).
  duck,
}

/// Callback signature for audio session interruptions.
///
/// [began] is `true` when the interruption starts (playback should pause)
/// and `false` when it ends (playback may resume).
typedef AudioInterruptionCallback = void Function(
  bool began,
  AudioInterruptionReason reason,
);

/// Manages the platform audio session (AVAudioSession on iOS/macOS,
/// AudioFocus on Android).
abstract class AudioPlaybackSession {
  /// Configures the session for exclusive playback that pauses other apps.
  Future<void> configureForPlayback();

  /// Activates the audio session, claiming audio focus.
  Future<void> activate();

  /// Deactivates the audio session, releasing audio focus.
  Future<void> deactivate();

  /// Registers a callback that fires on audio interruption events.
  ///
  /// Only one callback is supported at a time. Setting a new callback replaces
  /// the previous one. Pass `null` to unregister.
  set onInterruption(AudioInterruptionCallback? callback);
}

/// Production implementation backed by the `audio_session` package.
class SystemAudioPlaybackSession implements AudioPlaybackSession {
  static final Logger _logger = Logger('SystemAudioPlaybackSession');

  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  AudioInterruptionCallback? _onInterruption;

  @override
  set onInterruption(AudioInterruptionCallback? callback) {
    _onInterruption = callback;
  }

  @override
  Future<void> configureForPlayback() async {
    final session = await _session;
    await session.configure(
      const AudioSessionConfiguration(
        androidWillPauseWhenDucked: true,
        androidAudioAttributes: AndroidAudioAttributes(
          usage: AndroidAudioUsage.media,
          contentType: AndroidAudioContentType.music,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      ),
    );

    _listenForInterruptions(session);
  }

  @override
  Future<void> activate() async {
    final session = await _session;
    await session.setActive(true);
  }

  @override
  Future<void> deactivate() async {
    final session = await _session;
    await session.setActive(false);
  }

  /// Cleans up the interruption listener.
  Future<void> dispose() async {
    await _interruptionSubscription?.cancel();
    _interruptionSubscription = null;
    _onInterruption = null;
  }

  void _listenForInterruptions(AudioSession session) {
    _interruptionSubscription?.cancel();
    _interruptionSubscription = session.interruptionEventStream.listen(
      _handleInterruptionEvent,
    );
  }

  void _handleInterruptionEvent(AudioInterruptionEvent event) {
    final callback = _onInterruption;
    if (callback == null) return;

    final began = event.begin;
    final reason = _mapInterruptionType(event.type);

    _logger.info(
      'Audio interruption: began=$began, reason=$reason '
      '(type=${event.type})',
    );

    callback(began, reason);
  }

  AudioInterruptionReason _mapInterruptionType(AudioInterruptionType type) {
    return switch (type) {
      AudioInterruptionType.duck => AudioInterruptionReason.duck,
      AudioInterruptionType.pause =>
        AudioInterruptionReason.transientFocusLoss,
      AudioInterruptionType.unknown =>
        AudioInterruptionReason.externalInterruption,
    };
  }

  Future<AudioSession> get _session async {
    final cached = _audioSession;
    if (cached != null) {
      return cached;
    }

    final created = await AudioSession.instance;
    _audioSession = created;
    return created;
  }
}
