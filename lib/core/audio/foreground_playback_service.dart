import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';

/// Manages an Android foreground service notification while audio is playing.
///
/// On Android, the system may kill background processes aggressively. A
/// foreground service with a persistent notification keeps TempoDeck alive
/// while the metronome or setlist playback is running.
///
/// On iOS, macOS, and Windows this is a no-op — iOS uses `UIBackgroundModes:
/// audio` instead, and desktop platforms don't kill background apps.
abstract class ForegroundPlaybackService {
  /// Call when audio playback starts. Shows a persistent notification on
  /// Android; no-op on other platforms.
  Future<void> startForeground();

  /// Call when audio playback stops. Removes the notification on Android;
  /// no-op on other platforms.
  Future<void> stopForeground();
}

/// Production implementation that wraps `flutter_foreground_task` on Android.
class PlatformForegroundPlaybackService implements ForegroundPlaybackService {
  static final Logger _logger = Logger('ForegroundPlaybackService');
  static const int _serviceId = 800;

  bool _isRunning = false;
  bool _isInitialized = false;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> startForeground() async {
    if (!_isAndroid || _isRunning) return;

    _logger.info('Starting Android foreground service.');

    if (!_isInitialized) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'tempodeck_playback',
          channelName: 'TempoDeck Playback',
          channelDescription:
              'Shows while the metronome is running.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      _isInitialized = true;
    }

    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'TempoDeck',
      notificationText: 'Metronome is running',
    );

    _isRunning = true;
    _logger.info('Android foreground service started.');
  }

  @override
  Future<void> stopForeground() async {
    if (!_isAndroid || !_isRunning) return;

    _logger.info('Stopping Android foreground service.');
    await FlutterForegroundTask.stopService();
    _isRunning = false;
    _logger.info('Android foreground service stopped.');
  }
}
