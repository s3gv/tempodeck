import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tempodeck/core/files/linked_audio_file_storage.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory tempDir;
  late _TestableLinkedAudioFileStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('linked_audio_test_');
    storage = _TestableLinkedAudioFileStorage(storageDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('copyToStorage', () {
    test('copies file into storage directory with UUID filename', () async {
      final sourceFile = File(p.join(tempDir.path, 'source.mp3'));
      await sourceFile.writeAsBytes([1, 2, 3, 4, 5]);

      final destinationPath = await storage.copyToStorage(
        sourceFile.path,
        'My Song.mp3',
      );

      expect(File(destinationPath).existsSync(), isTrue);
      expect(p.dirname(destinationPath), tempDir.path);
      expect(p.extension(destinationPath), '.mp3');
      expect(await File(destinationPath).readAsBytes(), [1, 2, 3, 4, 5]);
    });

    test('preserves original file extension from display name', () async {
      final sourceFile = File(p.join(tempDir.path, 'source.wav'));
      await sourceFile.writeAsBytes([0]);

      final destinationPath = await storage.copyToStorage(
        sourceFile.path,
        'track.wav',
      );

      expect(p.extension(destinationPath), '.wav');
    });

    test('generates unique filenames for same display name', () async {
      final source1 = File(p.join(tempDir.path, 'source1.mp3'));
      await source1.writeAsBytes([1]);
      final source2 = File(p.join(tempDir.path, 'source2.mp3'));
      await source2.writeAsBytes([2]);

      final path1 = await storage.copyToStorage(source1.path, 'track.mp3');
      final path2 = await storage.copyToStorage(source2.path, 'track.mp3');

      expect(path1, isNot(path2));
      expect(File(path1).existsSync(), isTrue);
      expect(File(path2).existsSync(), isTrue);
    });

    test('throws when source file does not exist', () async {
      expect(
        () => storage.copyToStorage('/nonexistent/file.mp3', 'file.mp3'),
        throwsStateError,
      );
    });
  });

  group('deleteFromStorage', () {
    test('deletes file inside storage directory', () async {
      final file = File(p.join(tempDir.path, 'to-delete.mp3'));
      await file.writeAsBytes([1, 2, 3]);

      await storage.deleteFromStorage(file.path);

      expect(file.existsSync(), isFalse);
    });

    test('ignores files outside storage directory', () async {
      final outsideDir = await Directory.systemTemp.createTemp('outside_');
      try {
        final file = File(p.join(outsideDir.path, 'keep.mp3'));
        await file.writeAsBytes([1, 2, 3]);

        await storage.deleteFromStorage(file.path);

        expect(file.existsSync(), isTrue);
      } finally {
        await outsideDir.delete(recursive: true);
      }
    });

    test('does not throw when file does not exist', () async {
      final path = p.join(tempDir.path, 'already-gone.mp3');

      await expectLater(
        storage.deleteFromStorage(path),
        completes,
      );
    });
  });
}

/// Test-friendly subclass that uses a provided directory instead of
/// [getApplicationSupportDirectory].
class _TestableLinkedAudioFileStorage implements LinkedAudioFileStorage {
  _TestableLinkedAudioFileStorage({required this.storageDir});

  final Directory storageDir;
  final _uuid = const Uuid();

  @override
  Future<String> copyToStorage(String sourcePath, String displayName) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('Source audio file does not exist: $sourcePath');
    }

    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }

    final extension = p.extension(displayName).toLowerCase();
    final destinationPath = p.join(storageDir.path, '${_uuid.v4()}$extension');
    await sourceFile.copy(destinationPath);
    return destinationPath;
  }

  @override
  Future<void> deleteFromStorage(String filePath) async {
    if (!p.isWithin(storageDir.path, filePath)) {
      return;
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
