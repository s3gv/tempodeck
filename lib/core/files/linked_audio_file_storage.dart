import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copies picked audio files into app-owned storage and deletes them when no
/// longer needed.
///
/// On mobile, files selected via the system file picker receive temporary
/// sandbox URLs (iOS) or content URIs (Android) that expire after the app
/// restarts. Copying into [_linkedAudioDirectoryName] inside
/// [ApplicationSupport] gives TempoDeck a stable, app-owned path for playback,
/// preview, and export.
abstract class LinkedAudioFileStorage {
  /// Copies [sourcePath] into app-owned linked-audio storage and returns the
  /// destination path. The file is stored with a UUID-based filename to avoid
  /// collisions.
  Future<String> copyToStorage(String sourcePath, String displayName);

  /// Deletes [filePath] if it resides inside app-owned linked-audio storage.
  /// Files outside the storage directory are silently ignored (safety guard for
  /// desktop paths that should never be deleted).
  Future<void> deleteFromStorage(String filePath);
}

class AppLinkedAudioFileStorage implements LinkedAudioFileStorage {
  AppLinkedAudioFileStorage({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const String _linkedAudioDirectoryName = 'linked_audio';

  final Uuid _uuid;
  final _log = Logger('LinkedAudioFileStorage');

  @override
  Future<String> copyToStorage(String sourcePath, String displayName) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError(
        'Source audio file does not exist: $sourcePath',
      );
    }

    final storageDir = await _ensureStorageDirectory();
    final extension = p.extension(displayName).toLowerCase();
    final destinationPath = p.join(storageDir.path, '${_uuid.v4()}$extension');

    await sourceFile.copy(destinationPath);
    _log.fine('Copied linked audio to storage: $destinationPath');
    return destinationPath;
  }

  @override
  Future<void> deleteFromStorage(String filePath) async {
    final storageDir = await _storageDirectory();
    if (!p.isWithin(storageDir.path, filePath)) {
      _log.fine(
        'Skipping delete — file is not in app-owned storage: $filePath',
      );
      return;
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      _log.fine('Deleted linked audio from storage: $filePath');
    }
  }

  Future<Directory> _ensureStorageDirectory() async {
    final dir = await _storageDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _storageDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, _linkedAudioDirectoryName));
  }
}
