import '../db/app_database.dart';
import '../domain/metronome_preset.dart';
import '../validation/preset_write_validator.dart';
import 'preset_repository.dart';

class DriftPresetRepository implements PresetRepository {
  const DriftPresetRepository({
    required PresetDao presetDao,
    PresetWriteValidator presetWriteValidator = const PresetWriteValidator(),
  })  : _presetDao = presetDao,
        _presetWriteValidator = presetWriteValidator;

  final PresetDao _presetDao;
  final PresetWriteValidator _presetWriteValidator;

  @override
  Future<List<MetronomePreset>> getAllPresets() => _presetDao.getAllPresets();

  @override
  Stream<List<MetronomePreset>> watchAllPresets() =>
      _presetDao.watchAllPresets();

  @override
  Future<MetronomePreset?> getPresetById(String presetId) =>
      _presetDao.getPresetById(presetId);

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      _presetDao.watchPresetById(presetId);

  @override
  Future<void> savePreset(MetronomePreset preset) {
    _presetWriteValidator.validate(preset);
    return _presetDao.savePreset(preset);
  }

  @override
  Future<void> deletePreset(String presetId) =>
      _presetDao.deletePreset(presetId);
}
