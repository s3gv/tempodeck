import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/linked_audio_file.dart';

abstract class LinkedAudioPathRepairService {
  Future<LinkedAudioFile> repairIfNeeded(LinkedAudioFile linkedAudioFile);
}

abstract class LinkedAudioStoragePathProvider {
  Future<String> getApplicationDocumentsPath();
  Future<String> getApplicationSupportPath();
}

class SystemLinkedAudioStoragePathProvider
    implements LinkedAudioStoragePathProvider {
  const SystemLinkedAudioStoragePathProvider();

  @override
  Future<String> getApplicationDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  @override
  Future<String> getApplicationSupportPath() async {
    final directory = await getApplicationSupportDirectory();
    return directory.path;
  }
}

class AppLinkedAudioPathRepairService implements LinkedAudioPathRepairService {
  AppLinkedAudioPathRepairService({
    LinkedAudioStoragePathProvider? storagePathProvider,
  }) : _storagePathProvider =
           storagePathProvider ?? const SystemLinkedAudioStoragePathProvider();

  static const String _linkedAudioDirectoryName = 'linked_audio';

  final LinkedAudioStoragePathProvider _storagePathProvider;

  @override
  Future<LinkedAudioFile> repairIfNeeded(LinkedAudioFile linkedAudioFile) async {
    if (await File(linkedAudioFile.filePath).exists()) {
      return linkedAudioFile;
    }

    final repairedPath = await _findExistingPath(linkedAudioFile);
    if (repairedPath == null) {
      return linkedAudioFile;
    }

    return LinkedAudioFile(
      filePath: repairedPath,
      displayName: linkedAudioFile.displayName,
      offsetMilliseconds: linkedAudioFile.offsetMilliseconds,
      volumePercent: linkedAudioFile.volumePercent,
      playInLiveMode: linkedAudioFile.playInLiveMode,
    );
  }

  Future<String?> _findExistingPath(LinkedAudioFile linkedAudioFile) async {
    final documentsPath = await _storagePathProvider.getApplicationDocumentsPath();
    final supportPath = await _storagePathProvider.getApplicationSupportPath();
    final fileName = _resolveFileName(linkedAudioFile);
    final candidates = <String>[
      p.join(documentsPath, linkedAudioFile.displayName),
      p.join(documentsPath, fileName),
      p.join(supportPath, _linkedAudioDirectoryName, linkedAudioFile.displayName),
      p.join(supportPath, _linkedAudioDirectoryName, fileName),
    ];

    for (final candidate in candidates) {
      if (candidate.trim().isEmpty) {
        continue;
      }
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    return null;
  }

  String _resolveFileName(LinkedAudioFile linkedAudioFile) {
    final fileName = p.basename(linkedAudioFile.filePath);
    if (fileName.isNotEmpty) {
      return fileName;
    }

    return linkedAudioFile.displayName;
  }
}
