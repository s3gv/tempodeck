import '../db/app_database.dart';
import '../domain/song.dart';
import '../domain/song_beatmap.dart';
import '../validation/song_write_validator.dart';
import 'song_repository.dart';

class DriftSongRepository implements SongRepository {
  const DriftSongRepository({
    required SongDao songDao,
    SongWriteValidator songWriteValidator = const SongWriteValidator(),
  })  : _songDao = songDao,
        _songWriteValidator = songWriteValidator;

  final SongDao _songDao;
  final SongWriteValidator _songWriteValidator;

  @override
  Future<List<Song>> getAllSongs() => _songDao.getAllSongs();

  @override
  Stream<List<Song>> watchAllSongs() => _songDao.watchAllSongs();

  @override
  Future<Song?> getSongById(String songId) => _songDao.getSongById(songId);

  @override
  Stream<Song?> watchSongById(String songId) => _songDao.watchSongById(songId);

  @override
  Future<void> saveSong(Song song) {
    _songWriteValidator.validate(song);
    return _songDao.saveSong(song);
  }

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) {
    return _songDao.getSongBeatmap(songId);
  }

  @override
  Future<void> regenerateBeatmap(String songId) =>
      _songDao.regenerateBeatmap(songId);

  @override
  Future<void> deleteSong(String songId) => _songDao.deleteSong(songId);

  @override
  Future<Song> loadSong(String songId) async {
    final song = await _songDao.getSongById(songId);
    if (song == null) {
      throw StateError('Song not found: $songId');
    }

    return song;
  }
}
