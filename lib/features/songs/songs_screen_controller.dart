import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/audio_cue.dart';
import '../../core/domain/song.dart';
import '../../core/files/linked_audio_file_storage.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/service_providers.dart';

final songsScreenControllerProvider = Provider(
  (ref) => SongsScreenController(ref),
);

class SongsScreenController {
  SongsScreenController(this._ref);

  static const int _defaultStartBpm = 120;
  static const int _defaultBeatsPerBar = 4;
  static const int _defaultBeatUnit = 4;
  static const int _defaultCountInBars = 2;
  static const int _defaultEndBar = 32;
  static final _logger = Logger('SongsScreenController');

  final Ref _ref;
  final _uuid = const Uuid();

  Future<void> createSong(String title) async {
    final songId = _uuid.v4();
    final song = Song(
      id: songId,
      title: title,
      createdAt: DateTime.now(),
      startBpm: _defaultStartBpm,
      beatsPerBar: _defaultBeatsPerBar,
      beatUnit: _defaultBeatUnit,
      countInBars: _defaultCountInBars,
      endBar: _defaultEndBar,
    );
    final repository = _ref.read(songRepositoryProvider);
    await repository.saveSong(song);
    await repository.regenerateBeatmap(songId);
  }

  Future<void> renameSong(Song song, String newTitle) async {
    await _ref.read(songRepositoryProvider).saveSong(
          song.copyWith(title: newTitle.trim()),
        );
  }

  Future<void> deleteSong(String songId) async {
    final repository = _ref.read(songRepositoryProvider);
    final song = await repository.getSongById(songId);

    await repository.deleteSong(songId);

    if (song != null) {
      _cleanupSongAudioFiles(song);
    }
  }

  void _cleanupSongAudioFiles(Song song) {
    final storage = _ref.read(linkedAudioFileStorageProvider);

    if (song.linkedAudio != null) {
      storage.deleteFromStorage(song.linkedAudio!.filePath).catchError(
        (Object error) {
          _logger.warning('Failed to delete linked audio on song delete.', error);
        },
      );
    }

    _deleteCustomCueFiles(storage, song.songEvents);

    for (final loop in song.loops) {
      for (final ending in loop.alternativeEndings) {
        _deleteCustomCueFiles(storage, ending.songEvents);
      }
    }
  }

  void _deleteCustomCueFiles(
    LinkedAudioFileStorage storage,
    List<SongEvent> events,
  ) {
    for (final event in events) {
      if (event.audioCue?.type == AudioCueType.customFile &&
          event.audioCue?.customFilePath != null) {
        storage.deleteFromStorage(event.audioCue!.customFilePath!).catchError(
          (Object error) {
            _logger.warning(
              'Failed to delete custom cue file on song delete.',
              error,
            );
          },
        );
      }
    }
  }
}
