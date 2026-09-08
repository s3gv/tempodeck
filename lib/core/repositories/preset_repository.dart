import '../domain/metronome_preset.dart';

abstract class PresetRepository {
  Future<List<MetronomePreset>> getAllPresets();
  Stream<List<MetronomePreset>> watchAllPresets();
  Future<MetronomePreset?> getPresetById(String presetId);
  Stream<MetronomePreset?> watchPresetById(String presetId);
  Future<void> savePreset(MetronomePreset preset);
  Future<void> deletePreset(String presetId);
}
