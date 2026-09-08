import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/files/linked_audio_picker.dart';

void main() {
  test('requests custom audio extensions from the picker client', () async {
    final client = _FakeLinkedAudioPickerClient();
    final picker = FilePickerLinkedAudioPicker(client: client);

    await picker.pickAudioFile();

    expect(client.allowedExtensions, supportedLinkedAudioExtensions);
  });

  test('maps a picked file into the app model', () async {
    final client = _FakeLinkedAudioPickerClient(
      result: FilePickerResult([
        PlatformFile(
          name: 'Loop.wav',
          path: '/tmp/loop.wav',
          size: 42,
        ),
      ]),
    );
    final picker = FilePickerLinkedAudioPicker(client: client);

    final pickedFile = await picker.pickAudioFile();

    expect(pickedFile, isNotNull);
    expect(pickedFile!.filePath, '/tmp/loop.wav');
    expect(pickedFile.displayName, 'Loop.wav');
  });

  test('throws when the picker result has no local path', () async {
    final client = _FakeLinkedAudioPickerClient(
      result: FilePickerResult([
        PlatformFile(
          name: 'Loop.wav',
          bytes: Uint8List.fromList(const [1, 2, 3]),
          size: 3,
        ),
      ]),
    );
    final picker = FilePickerLinkedAudioPicker(client: client);

    expect(
      picker.pickAudioFile,
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeLinkedAudioPickerClient implements LinkedAudioPickerClient {
  _FakeLinkedAudioPickerClient({this.result});

  final FilePickerResult? result;
  List<String>? allowedExtensions;

  @override
  Future<FilePickerResult?> pickAudioFile({
    required List<String> allowedExtensions,
  }) async {
    this.allowedExtensions = allowedExtensions;
    return result;
  }
}
