import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/repositories/drift_setlist_repository.dart';

void main() {
  late AppDatabase database;
  late DriftSetlistRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftSetlistRepository(setlistDao: database.setlistDao);
  });

  tearDown(() async {
    await database.close();
  });

  test('persists and reloads setlists through the repository contract',
      () async {
    final setlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
        ),
      ],
    );

    await repository.saveSetlist(setlist);

    final loadedSetlist = await repository.getSetlistById(setlist.id);
    final allSetlists = await repository.getAllSetlists();

    expect(loadedSetlist, isNotNull);
    expect(loadedSetlist!.id, setlist.id);
    expect(loadedSetlist.title, setlist.title);
    expect(allSetlists.map((item) => item.id).toList(), ['setlist-1']);
  });

  test('watchAllSetlists emits repository updates', () async {
    final emittedSetlists = <List<Setlist>>[];
    final setlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );
    final subscription =
        repository.watchAllSetlists().listen(emittedSetlists.add);

    await Future<void>.delayed(Duration.zero);
    await repository.saveSetlist(setlist);
    await Future<void>.delayed(Duration.zero);
    await repository.deleteSetlist(setlist.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSetlists.first, isEmpty);
    expect(emittedSetlists[1].map((item) => item.id).toList(), ['setlist-1']);
    expect(emittedSetlists.last, isEmpty);
  });

  test('watchSetlistById emits setlist updates and null after deletion',
      () async {
    final emittedSetlists = <Setlist?>[];
    final setlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );
    final subscription =
        repository.watchSetlistById(setlist.id).listen(emittedSetlists.add);

    await Future<void>.delayed(Duration.zero);
    await repository.saveSetlist(setlist);
    await Future<void>.delayed(Duration.zero);
    await repository.deleteSetlist(setlist.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSetlists.first, isNull);
    expect(emittedSetlists[1], isNotNull);
    expect(emittedSetlists[1]!.id, setlist.id);
    expect(emittedSetlists.last, isNull);
  });

  test('loadSetlist returns the stored setlist for export source loading',
      () async {
    final setlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );

    await repository.saveSetlist(setlist);

    final loadedSetlist = await repository.loadSetlist(setlist.id);

    expect(loadedSetlist.id, setlist.id);
    expect(loadedSetlist.title, setlist.title);
  });

  test('loadSetlist throws when the setlist does not exist', () async {
    await expectLater(
      repository.loadSetlist('missing-setlist'),
      throwsA(isA<StateError>()),
    );
  });

  test('saveSetlist rejects invalid setlist data before writing', () {
    final invalidSetlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
          transitionSteps: [
            SetlistTransitionStep(
              id: 'step-1',
              type: SetlistTransitionStepType.audio,
              value: 0,
              audioCue: AudioCue(
                type: AudioCueType.customFile,
                customFilePath: '',
              ),
            ),
          ],
        ),
      ],
    );

    expect(
      () => repository.saveSetlist(invalidSetlist),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('saveSetlist rejects blank titles before writing', () {
    final invalidSetlist = Setlist(
      id: 'setlist-1',
      title: '   ',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );

    expect(
      () => repository.saveSetlist(invalidSetlist),
      throwsA(isA<ArgumentError>()),
    );
  });
}
