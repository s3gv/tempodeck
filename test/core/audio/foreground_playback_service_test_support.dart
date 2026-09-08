import 'package:tempodeck/core/audio/foreground_playback_service.dart';

class FakeForegroundPlaybackService implements ForegroundPlaybackService {
  int startCallCount = 0;
  int stopCallCount = 0;
  bool isRunning = false;

  @override
  Future<void> startForeground() async {
    startCallCount += 1;
    isRunning = true;
  }

  @override
  Future<void> stopForeground() async {
    stopCallCount += 1;
    isRunning = false;
  }
}
