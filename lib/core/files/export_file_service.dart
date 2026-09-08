import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Service for saving or sharing exported audio files.
///
/// [IosExportFileService] opens the iOS share sheet (which includes "Save to
/// Files").
/// [AndroidExportFileService] opens a save-file dialog via [FilePicker] since
/// Android's share sheet does not offer a native "save to device" option.
/// [DesktopExportFileService] opens a save-file dialog (macOS/Windows).
abstract class ExportFileService {
  /// Presents the exported file at [filePath] to the user for saving.
  ///
  /// [fileName] is the suggested display name (e.g. `My Song.mp3`).
  Future<void> saveExportedFile(String filePath, String fileName);
}

/// Opens the iOS share sheet which natively includes "Save to Files".
class IosExportFileService implements ExportFileService {
  const IosExportFileService();

  @override
  Future<void> saveExportedFile(String filePath, String fileName) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(filePath, name: fileName)]),
    );
  }
}

/// Opens a save-file dialog on Android via [FilePicker].
///
/// Android requires passing [bytes] directly to [FilePicker.saveFile] because
/// the returned path is a content URI that cannot be written to with
/// [File.copy].
class AndroidExportFileService implements ExportFileService {
  const AndroidExportFileService();

  @override
  Future<void> saveExportedFile(String filePath, String fileName) async {
    final bytes = await File(filePath).readAsBytes();
    await FilePicker.platform.saveFile(
      dialogTitle: 'Save Export',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['mp3'],
      bytes: bytes,
    );
  }
}

/// Opens a save-file dialog (macOS/Windows).
class DesktopExportFileService implements ExportFileService {
  const DesktopExportFileService();

  @override
  Future<void> saveExportedFile(String filePath, String fileName) async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Export',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );
    if (outputPath == null) return;

    await File(filePath).copy(outputPath);
  }
}
