import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';

import 'i_audio_device_service.dart';
import 'i_audio_engine.dart';
import 'soloud_client.dart';

/// Real implementation backed by flutter_soloud's device enumeration.
///
/// Uses miniaudio under the hood — CoreAudio on macOS, WASAPI on Windows.
/// Mobile platforms only expose the system default device.
///
/// **Device switching strategy:**
/// - Specific device → `changeDevice(device)`. Miniaudio destroys the old
///   device and creates a new one pointing at the target. Loaded SoLoud
///   sources survive in memory and play through the new device.
/// - System Default → full engine `dispose()` + `initialize()` cycle.
///   SoLoud's `changeDevice` always passes a concrete device ID to miniaudio,
///   so there is no way to tell it "follow the OS default". Only a fresh
///   `init()` (which passes `pDeviceID = NULL`) achieves true OS-default
///   routing. The engine reload also re-loads click sounds and cue sources.
class SoLoudAudioDeviceService implements IAudioDeviceService {
  SoLoudAudioDeviceService({
    required SoLoudClient soLoudClient,
    required IAudioEngine audioEngine,
  })  : _soLoudClient = soLoudClient,
        _audioEngine = audioEngine;

  static final Logger _logger = Logger('SoLoudAudioDeviceService');

  final SoLoudClient _soLoudClient;
  final IAudioEngine _audioEngine;
  String? _selectedDeviceId;

  @override
  String? get selectedDeviceId => _selectedDeviceId;

  static const _systemDefault = AudioOutputDevice(
    id: null,
    name: 'System Default',
    isDefault: true,
  );

  @override
  Future<List<AudioOutputDevice>> listDevices() async {
    try {
      final devices = _soLoudClient.listPlaybackDevices();
      return [
        _systemDefault,
        ...devices.map(
          (device) => AudioOutputDevice(
            id: device.id.toString(),
            name: device.name,
            isDefault: false,
          ),
        ),
      ];
    } catch (error, stackTrace) {
      _logger.warning('Failed to list playback devices.', error, stackTrace);
      return const [_systemDefault];
    }
  }

  @override
  Future<String?> selectDevice(String? deviceId) async {
    try {
      if (deviceId == null) {
        await _switchToSystemDefault();
      } else {
        await _switchToSpecificDevice(deviceId);
      }
      _selectedDeviceId = deviceId;
    } catch (error, stackTrace) {
      _logger.severe('Failed to switch audio device.', error, stackTrace);
      // Try to recover by reinitializing on the OS default.
      try {
        await _audioEngine.dispose();
        await _audioEngine.initialize();
        _selectedDeviceId = null;
      } catch (_) {
        // Exhausted recovery options.
      }
    }
    return _selectedDeviceId;
  }

  /// Reinitialize the entire engine so miniaudio picks up the OS default.
  Future<void> _switchToSystemDefault() async {
    _logger.info('Switching to System Default via engine reinit.');
    await _audioEngine.dispose();
    await _audioEngine.initialize();
    _logger.info('Engine reinitialized on OS default device.');
  }

  /// Use SoLoud's changeDevice to hot-switch to a specific device.
  Future<void> _switchToSpecificDevice(String deviceId) async {
    final targetId = int.tryParse(deviceId);
    if (targetId == null) {
      _logger.warning('Invalid device ID: $deviceId');
      return;
    }

    // Always get a fresh device list — the internal pPlaybackInfos array
    // is rebuilt on each call, and changeDevice indexes into it.
    final devices = _soLoudClient.listPlaybackDevices();
    final target = _findDeviceById(devices, targetId);
    if (target == null) {
      _logger.warning('Device with ID $deviceId not found.');
      return;
    }

    _logger.info(
      'Switching audio output to: ${target.name} (ID: ${target.id})',
    );
    _soLoudClient.changeDevice(newDevice: target);
    _logger.info('Audio output switched to: ${target.name}.');
  }

  PlaybackDevice? _findDeviceById(
    List<PlaybackDevice> devices,
    int targetId,
  ) {
    for (final device in devices) {
      if (device.id == targetId) return device;
    }
    return null;
  }
}
