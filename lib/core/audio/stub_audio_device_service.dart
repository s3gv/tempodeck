import 'i_audio_device_service.dart';

/// Stub implementation that only exposes "System Default".
///
/// Used on all platforms until real device enumeration is implemented.
/// SoLoud does not yet expose output device selection, so this placeholder
/// keeps the settings UI functional without a backend.
class StubAudioDeviceService implements IAudioDeviceService {
  static const _systemDefault = AudioOutputDevice(
    id: null,
    name: 'System Default',
    isDefault: true,
  );

  @override
  String? get selectedDeviceId => null;

  @override
  Future<List<AudioOutputDevice>> listDevices() async {
    return const [_systemDefault];
  }

  @override
  Future<String?> selectDevice(String? deviceId) async {
    // No-op until real device selection is implemented.
    return null;
  }
}
