import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/files/linked_audio_file_storage.dart';
import 'package:tempodeck/core/files/linked_audio_import_service.dart';
import 'package:tempodeck/core/files/linked_audio_picker.dart';

void main() {
  group('ValidatingLinkedAudioImportService', () {
    test('returns the original path without copying the file', () async {
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'tempodeck_source_',
      );
      addTearDown(() async {
        if (await sourceDirectory.exists()) {
          await sourceDirectory.delete(recursive: true);
        }
      });

      final sourceFile = File('${sourceDirectory.path}/echoes.mp3');
      await sourceFile.writeAsString('audio');

      const service = ValidatingLinkedAudioImportService();

      final importedFile = await service.importPickedAudioFile(
        PickedLinkedAudioFile(
          filePath: sourceFile.path,
          displayName: 'echoes.mp3',
        ),
      );

      // Path must point to the original file, not a copy.
      expect(importedFile.filePath, sourceFile.path);
      expect(importedFile.displayName, 'echoes.mp3');
    });

    test('throws when picked file does not exist', () async {
      const service = ValidatingLinkedAudioImportService();

      expect(
        () => service.importPickedAudioFile(
          const PickedLinkedAudioFile(
            filePath: '/nonexistent/audio.mp3',
            displayName: 'audio.mp3',
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('CopyingLinkedAudioImportService', () {
    late Directory tempDir;
    late _FakeLinkedAudioFileStorage fakeStorage;
    late CopyingLinkedAudioImportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tempodeck_copy_');
      fakeStorage = _FakeLinkedAudioFileStorage(storageDir: tempDir);
      service = CopyingLinkedAudioImportService(fileStorage: fakeStorage);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('copies file to storage and returns new path', () async {
      final sourceFile = File('${tempDir.path}/source.mp3');
      await sourceFile.writeAsBytes([1, 2, 3]);

      final importedFile = await service.importPickedAudioFile(
        PickedLinkedAudioFile(
          filePath: sourceFile.path,
          displayName: 'My Track.mp3',
        ),
      );

      expect(importedFile.filePath, isNot(sourceFile.path));
      expect(importedFile.displayName, 'My Track.mp3');
      expect(File(importedFile.filePath).existsSync(), isTrue);
      expect(fakeStorage.copyCount, 1);
    });

    test('throws when source file does not exist', () async {
      expect(
        () => service.importPickedAudioFile(
          const PickedLinkedAudioFile(
            filePath: '/nonexistent/audio.mp3',
            displayName: 'audio.mp3',
          ),
        ),
        throwsStateError,
      );
    });
  });
}

class _FakeLinkedAudioFileStorage implements LinkedAudioFileStorage {
  _FakeLinkedAudioFileStorage({required this.storageDir});

  final Directory storageDir;
  int copyCount = 0;
  int deleteCount = 0;

  @override
  Future<String> copyToStorage(String sourcePath, String displayName) async {
    copyCount++;
    final dest = '${storageDir.path}/copied_$copyCount.mp3';
    await File(sourcePath).copy(dest);
    return dest;
  }

  @override
  Future<void> deleteFromStorage(String filePath) async {
    deleteCount++;
  }
}
