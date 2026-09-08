import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import '../audio/audio_playback_session.dart';
import '../audio/foreground_playback_service.dart';
import '../audio/i_audio_engine.dart';

final _logger = Logger('AudioLifecycleObserver');

/// Stops audio playback when the app is backgrounded (mobile) or terminated,
/// and handles platform audio interruptions (phone calls, Siri, etc.).
///
/// Wraps a child widget and listens to [AppLifecycleState] changes. On mobile
/// platforms, playback is stopped when the app enters the paused or detached
/// state. On all platforms, the audio engine is disposed when the widget is
/// removed from the tree (app shutdown).
///
/// Audio interruptions (e.g. incoming phone call) stop playback immediately.
/// Transient interruptions and ducking are treated identically — the metronome
/// must stop because a ducked or paused click is useless for practicing.
class AudioLifecycleObserver extends StatefulWidget {
  const AudioLifecycleObserver({
    required this.audioEngine,
    required this.playbackSession,
    required this.foregroundService,
    required this.child,
    this.onExternalStop,
    super.key,
  });

  final IAudioEngine audioEngine;
  final AudioPlaybackSession playbackSession;
  final ForegroundPlaybackService foregroundService;

  /// Called after playback is stopped externally (interruption or app
  /// backgrounded). Allows the live controller to sync its UI state.
  final VoidCallback? onExternalStop;

  final Widget child;

  @override
  State<AudioLifecycleObserver> createState() =>
      _AudioLifecycleObserverState();
}

class _AudioLifecycleObserverState extends State<AudioLifecycleObserver>
    with WidgetsBindingObserver {
  static const _mobileStopStates = {
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  };

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerInterruptionHandler();
  }

  @override
  void didUpdateWidget(AudioLifecycleObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackSession != widget.playbackSession) {
      oldWidget.playbackSession.onInterruption = null;
      _registerInterruptionHandler();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.playbackSession.onInterruption = null;
    unawaited(_safeDispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isMobile && _mobileStopStates.contains(state)) {
      _logger.info('App lifecycle $state — stopping playback.');
      unawaited(_safeStop());
    }
    // On desktop, detached means the window is closing. Dispose the engine
    // eagerly so SoLoud's native resources are freed before the Dart VM
    // shuts down (avoids the "GetFfiCallbackMetadata called after shutdown"
    // crash and the macOS "unexpectedly quit" dialog).
    if (!_isMobile && state == AppLifecycleState.detached) {
      _logger.info('Desktop app detached — disposing audio engine.');
      unawaited(_safeDispose());
    }
  }

  void _registerInterruptionHandler() {
    widget.playbackSession.onInterruption = _handleInterruption;
  }

  void _handleInterruption(bool began, AudioInterruptionReason reason) {
    if (!began) {
      // Interruption ended — we do NOT auto-resume because a metronome
      // resuming unexpectedly after a phone call is disruptive.
      _logger.info('Audio interruption ended (reason=$reason). '
          'Not auto-resuming — user must restart manually.');
      return;
    }

    _logger.info('Audio interruption began (reason=$reason) — '
        'stopping playback.');
    unawaited(_safeStop());
  }

  Future<void> _safeStop() async {
    try {
      await widget.audioEngine.stop();
      await widget.foregroundService.stopForeground();
      widget.onExternalStop?.call();
    } catch (error, stackTrace) {
      _logger.warning('Failed to stop audio engine.', error, stackTrace);
    }
  }

  Future<void> _safeDispose() async {
    try {
      _logger.info('App shutting down — disposing audio engine.');
      await widget.foregroundService.stopForeground();
      await widget.audioEngine.dispose();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to dispose audio engine.',
        error,
        stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
