import '../audio/export_project_source_resolver.dart';
import '../domain/song.dart';
import '../domain/song_beatmap.dart';

abstract class SongRepository implements SongExportSourceLoader {
  Future<List<Song>> getAllSongs();
  Stream<List<Song>> watchAllSongs();
  Future<Song?> getSongById(String songId);
  Stream<Song?> watchSongById(String songId);
  Future<SongBeatmap> loadSongBeatmap(String songId);
  Future<void> saveSong(Song song);
  Future<void> regenerateBeatmap(String songId);
  Future<void> deleteSong(String songId);
}
