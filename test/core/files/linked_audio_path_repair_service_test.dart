import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/files/linked_audio_path_repair_service.dart';

void main() {
  test('repairs a stale sandbox temp path from a matching documents file', () async {
    final documentsDirectory = await Directory.systemTemp.createTemp(
      'tempodeck_documents_',
    );
    final supportDirectory = await Directory.systemTemp.createTemp(
      'tempodeck_support_',
    );
    addTearDown(() async {
      if (await documentsDirectory.exists()) {
        await documentsDirectory.delete(recursive: true);
      }
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    });

    final repairedFile = File('${documentsDirectory.path}/echoes.mp3');
    await repairedFile.writeAsString('audio');

    final service = AppLinkedAudioPathRepairService(
      storagePathProvider: _FakeLinkedAudioStoragePathProvider(
        documentsPath: documentsDirectory.path,
        supportPath: supportDirectory.path,
      ),
    );

    final repaired = await service.repairIfNeeded(
      const LinkedAudioFile(
        filePath: '/old/simulator/container/tmp/echoes.mp3',
        displayName: 'echoes.mp3',
        offsetMilliseconds: 2003,
      ),
    );

    expect(repaired.filePath, repairedFile.path);
    expect(repaired.displayName, 'echoes.mp3');
    expect(repaired.offsetMilliseconds, 2003);
  });
}

class _FakeLinkedAudioStoragePathProvider
    implements LinkedAudioStoragePathProvider {
  const _FakeLinkedAudioStoragePathProvider({
    required this.documentsPath,
    required this.supportPath,
  });

  final String documentsPath;
  final String supportPath;

  @override
  Future<String> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String> getApplicationSupportPath() async => supportPath;
}
