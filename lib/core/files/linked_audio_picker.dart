import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';

const List<String> supportedLinkedAudioExtensions = [
  'aac',
  'aif',
  'aiff',
  'flac',
  'm4a',
  'mp3',
  'mp4',
  'ogg',
  'wav',
];

class PickedLinkedAudioFile {
  const PickedLinkedAudioFile({
    required this.filePath,
    required this.displayName,
  });

  final String filePath;
  final String displayName;
}

abstract class LinkedAudioPicker {
  Future<PickedLinkedAudioFile?> pickAudioFile();
}

abstract class LinkedAudioPickerClient {
  Future<FilePickerResult?> pickAudioFile({
    required List<String> allowedExtensions,
  });
}

class SystemLinkedAudioPickerClient implements LinkedAudioPickerClient {
  const SystemLinkedAudioPickerClient();

  @override
  Future<FilePickerResult?> pickAudioFile({
    required List<String> allowedExtensions,
  }) {
    // lockParentWindow is only supported on mobile platforms.
    // On desktop (macOS/Windows) it can prevent the dialog from opening.
    final isMobile = Platform.isIOS || Platform.isAndroid;
    return FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      dialogTitle: 'Select audio file',
      lockParentWindow: isMobile,
    );
  }
}

class FilePickerLinkedAudioPicker implements LinkedAudioPicker {
  const FilePickerLinkedAudioPicker({
    LinkedAudioPickerClient? client,
  }) : _client = client ?? const SystemLinkedAudioPickerClient();

  final LinkedAudioPickerClient _client;

  @override
  Future<PickedLinkedAudioFile?> pickAudioFile() async {
    final result = await _client.pickAudioFile(
      allowedExtensions: supportedLinkedAudioExtensions,
    );
    if (result == null) {
      return null;
    }

    final file = result.files.single;
    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      throw StateError('Picked audio files must expose a local file path.');
    }

    return PickedLinkedAudioFile(
      filePath: path,
      displayName: file.name,
    );
  }
}
