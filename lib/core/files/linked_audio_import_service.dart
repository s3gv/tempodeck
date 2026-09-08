import 'dart:io';

import 'linked_audio_file_storage.dart';
import 'linked_audio_picker.dart';

/// Validates a picked audio file and returns it for storage.
abstract class LinkedAudioImportService {
  Future<PickedLinkedAudioFile> importPickedAudioFile(
    PickedLinkedAudioFile pickedFile,
  );
}

/// Desktop implementation: files remain at their original filesystem location.
/// TempoDeck stores only the path and metadata — it never copies, moves, or
/// duplicates user files into app-owned folders.
class ValidatingLinkedAudioImportService implements LinkedAudioImportService {
  const ValidatingLinkedAudioImportService();

  @override
  Future<PickedLinkedAudioFile> importPickedAudioFile(
    PickedLinkedAudioFile pickedFile,
  ) async {
    final sourceFile = File(pickedFile.filePath);
    if (!await sourceFile.exists()) {
      throw StateError(
        'Picked audio file does not exist: ${pickedFile.filePath}',
      );
    }

    return pickedFile;
  }
}

/// Mobile implementation: copies the picked file into app-owned storage so
/// the path survives app restarts. On iOS, file picker URLs are temporary
/// sandbox grants that expire. On Android, content:// URIs expire similarly.
class CopyingLinkedAudioImportService implements LinkedAudioImportService {
  const CopyingLinkedAudioImportService({
    required LinkedAudioFileStorage fileStorage,
  }) : _fileStorage = fileStorage;

  final LinkedAudioFileStorage _fileStorage;

  @override
  Future<PickedLinkedAudioFile> importPickedAudioFile(
    PickedLinkedAudioFile pickedFile,
  ) async {
    final sourceFile = File(pickedFile.filePath);
    if (!await sourceFile.exists()) {
      throw StateError(
        'Picked audio file does not exist: ${pickedFile.filePath}',
      );
    }

    final storagePath = await _fileStorage.copyToStorage(
      pickedFile.filePath,
      pickedFile.displayName,
    );

    return PickedLinkedAudioFile(
      filePath: storagePath,
      displayName: pickedFile.displayName,
    );
  }
}
