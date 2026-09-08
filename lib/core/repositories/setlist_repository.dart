import '../audio/export_project_source_resolver.dart';
import '../domain/setlist.dart';

abstract class SetlistRepository implements SetlistExportSourceLoader {
  Future<List<Setlist>> getAllSetlists();
  Stream<List<Setlist>> watchAllSetlists();
  Future<Setlist?> getSetlistById(String setlistId);
  Stream<Setlist?> watchSetlistById(String setlistId);
  Future<void> saveSetlist(Setlist setlist);
  Future<void> deleteSetlist(String setlistId);
}
