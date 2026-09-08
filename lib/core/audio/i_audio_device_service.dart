/// Represents an audio output device available on the system.
class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  /// Platform-specific device identifier, or `null` for the system default.
  final String? id;

  /// Human-readable device name shown in the UI.
  final String name;

  /// Whether this is the operating system's default output device.
  final bool isDefault;
}

/// Provides access to the platform's audio output device list.
///
/// Desktop platforms (macOS, Windows) allow the user to choose which speakers
/// or headphones receive audio. Mobile platforms delegate this to the OS and
/// do not expose device selection, so mobile builds should use a no-op stub.
abstract class IAudioDeviceService {
  /// Returns all available output devices, including a "System Default" entry.
  Future<List<AudioOutputDevice>> listDevices();

  /// Selects the output device. Pass `null` to use the system default.
  ///
  /// Returns the device ID that is actually active after the switch, or `null`
  /// when the system default is active (including fallback after an error).
  Future<String?> selectDevice(String? deviceId);

  /// The currently selected device ID, or `null` for system default.
  String? get selectedDeviceId;
}
