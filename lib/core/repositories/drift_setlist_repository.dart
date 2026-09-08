import '../db/app_database.dart';
import '../domain/setlist.dart';
import '../validation/setlist_write_validator.dart';
import 'setlist_repository.dart';

class DriftSetlistRepository implements SetlistRepository {
  const DriftSetlistRepository({
    required SetlistDao setlistDao,
    SetlistWriteValidator setlistWriteValidator = const SetlistWriteValidator(),
  })  : _setlistDao = setlistDao,
        _setlistWriteValidator = setlistWriteValidator;

  final SetlistDao _setlistDao;
  final SetlistWriteValidator _setlistWriteValidator;

  @override
  Future<List<Setlist>> getAllSetlists() => _setlistDao.getAllSetlists();

  @override
  Stream<List<Setlist>> watchAllSetlists() => _setlistDao.watchAllSetlists();

  @override
  Future<Setlist?> getSetlistById(String setlistId) =>
      _setlistDao.getSetlistById(setlistId);

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) =>
      _setlistDao.watchSetlistById(setlistId);

  @override
  Future<void> saveSetlist(Setlist setlist) {
    _setlistWriteValidator.validate(setlist);
    return _setlistDao.saveSetlist(setlist);
  }

  @override
  Future<void> deleteSetlist(String setlistId) =>
      _setlistDao.deleteSetlist(setlistId);

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    final setlist = await _setlistDao.getSetlistById(setlistId);
    if (setlist == null) {
      throw StateError('Setlist not found: $setlistId');
    }

    return setlist;
  }
}
