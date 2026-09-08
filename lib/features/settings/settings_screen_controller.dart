import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/app_variant_provider.dart';
import '../../core/providers/service_providers.dart';
import 'settings_screen_state.dart';

final settingsScreenControllerProvider =
    NotifierProvider<SettingsScreenController, SettingsScreenState>(
  SettingsScreenController.new,
);

class SettingsScreenController extends Notifier<SettingsScreenState> {
  static final Logger _logger = Logger('SettingsScreenController');

  static const String _backupFileName = 'TempoDeck-Backup.json';

  @override
  SettingsScreenState build() => const SettingsScreenState();

  Future<void> exportBackup() async {
    state = state.copyWith(
      isExporting: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );

    try {
      final exporter = ref.read(backupExporterProvider);
      final jsonString = await exporter.exportJson();
      final saved = await _saveBackupFile(jsonString);
      state = state.copyWith(
        isExporting: false,
        successMessage: saved ? 'Backup exported successfully.' : null,
      );
    } catch (error, stackTrace) {
      _logger.warning('Failed to export backup.', error, stackTrace);
      state = state.copyWith(
        isExporting: false,
        errorMessage: 'Export failed: $error',
      );
    }
  }

  /// Picks a backup file, asks for confirmation via [confirm], then restores.
  ///
  /// [confirm] is called after the file is picked and validated. It should
  /// return `true` to proceed with the restore, `false` to cancel.
  Future<void> importBackup({
    required Future<bool> Function() confirm,
  }) async {
    state = state.copyWith(
      isImporting: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );

    try {
      final jsonString = await _pickBackupFile();
      if (jsonString == null) {
        state = state.copyWith(isImporting: false);
        return;
      }

      final confirmed = await confirm();
      if (!confirmed) {
        state = state.copyWith(isImporting: false);
        return;
      }

      final restorer = ref.read(backupRestorerProvider);
      await restorer.restoreJson(jsonString);

      state = state.copyWith(
        isImporting: false,
        successMessage: 'Backup restored successfully.',
      );
    } catch (error, stackTrace) {
      _logger.warning('Failed to import backup.', error, stackTrace);
      state = state.copyWith(
        isImporting: false,
        errorMessage: 'Import failed: $error',
      );
    }
  }

  /// Returns the JSON content of the picked file, or `null` when the user
  /// cancelled the picker.
  Future<String?> _pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return null;

    final filePath = result.files.single.path;
    if (filePath == null) return null;

    return File(filePath).readAsString();
  }

  void clearMessages() {
    state = state.copyWith(
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );
  }

  /// Returns `true` when the file was actually written, `false` when the user
  /// cancelled the save dialog.
  Future<bool> _saveBackupFile(String jsonString) async {
    final variant = ref.read(appVariantProvider);

    if (variant.isDesktop) {
      return _saveBackupDesktop(jsonString);
    } else if (Platform.isIOS) {
      await _saveBackupIos(jsonString);
      return true;
    } else {
      return _saveBackupAndroid(jsonString);
    }
  }

  Future<bool> _saveBackupDesktop(String jsonString) async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Backup',
      fileName: _backupFileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (outputPath == null) return false;

    await File(outputPath).writeAsString(jsonString);
    return true;
  }

  Future<void> _saveBackupIos(String jsonString) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$_backupFileName');
    await tempFile.writeAsString(jsonString);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(tempFile.path, name: _backupFileName)]),
    );
  }

  Future<bool> _saveBackupAndroid(String jsonString) async {
    final bytes = utf8.encode(jsonString);
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Backup',
      fileName: _backupFileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    return outputPath != null;
  }
}

