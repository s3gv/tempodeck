import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';

void main() {
  late AppDatabase database;
  late SetlistDao dao;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dao = database.setlistDao;
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and reloads a full setlist aggregate', () async {
    final setlist = Setlist(
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
              type: SetlistTransitionStepType.countInBars,
              value: 2,
            ),
            SetlistTransitionStep(
              id: 'step-2',
              type: SetlistTransitionStepType.audio,
              value: 0,
              audioCue: AudioCue(
                type: AudioCueType.voice,
                voiceText: 'Next song',
                voiceIdentifier: 'en-US',
                volumePercent: 80,
              ),
            ),
          ],
        ),
        SetlistItem(
          id: 'item-2',
          songId: 'song-2',
          songTitle: 'Finale',
          playbackEnabled: false,
          playAttachedAudio: false,
          transitionSteps: [
            SetlistTransitionStep(
              id: 'step-3',
              type: SetlistTransitionStepType.manual,
              value: 0,
            ),
          ],
        ),
      ],
    );

    await dao.saveSetlist(setlist);

    final loadedSetlist = await dao.getSetlistById(setlist.id);

    expect(loadedSetlist, isNotNull);
    _expectSetlistsEqual(loadedSetlist!, setlist);
  });

  test('updates setlist items and replaces child steps on overwrite', () async {
    final originalSetlist = Setlist(
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
              type: SetlistTransitionStepType.countInBars,
              value: 2,
            ),
          ],
        ),
      ],
    );
    final updatedSetlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set v2',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      items: const [
        SetlistItem(
          id: 'item-2',
          songId: 'song-2',
          songTitle: 'Finale',
          playAttachedAudio: false,
          transitionSteps: [
            SetlistTransitionStep(
              id: 'step-2',
              type: SetlistTransitionStepType.pauseTimer,
              value: 4000,
            ),
          ],
        ),
      ],
    );

    await dao.saveSetlist(originalSetlist);
    await dao.saveSetlist(updatedSetlist);

    final loadedSetlist = await dao.getSetlistById(updatedSetlist.id);
    final remainingSteps =
        await database.select(database.setlistTransitionSteps).get();

    expect(loadedSetlist, isNotNull);
    _expectSetlistsEqual(loadedSetlist!, updatedSetlist);
    expect(remainingSteps.map((step) => step.id).toList(), ['step-2']);
  });

  test('lists setlists newest first', () async {
    final olderSetlist = Setlist(
      id: 'setlist-1',
      title: 'Older',
      createdAt: DateTime.utc(2026, 3, 9, 12),
    );
    final newerSetlist = Setlist(
      id: 'setlist-2',
      title: 'Newer',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );

    await dao.saveSetlist(olderSetlist);
    await dao.saveSetlist(newerSetlist);

    final setlists = await dao.getAllSetlists();

    expect(
      setlists.map((setlist) => setlist.id).toList(),
      ['setlist-2', 'setlist-1'],
    );
  });

  test('deletes setlists and cascades to child rows', () async {
    final setlist = Setlist(
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
              type: SetlistTransitionStepType.countInBars,
              value: 2,
            ),
          ],
        ),
      ],
    );

    await dao.saveSetlist(setlist);
    await dao.deleteSetlist(setlist.id);

    final loadedSetlist = await dao.getSetlistById(setlist.id);
    final remainingItems = await database.select(database.setlistItems).get();
    final remainingSteps =
        await database.select(database.setlistTransitionSteps).get();

    expect(loadedSetlist, isNull);
    expect(remainingItems, isEmpty);
    expect(remainingSteps, isEmpty);
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
        dao.watchSetlistById(setlist.id).listen(emittedSetlists.add);

    await Future<void>.delayed(Duration.zero);
    await dao.saveSetlist(setlist);
    await Future<void>.delayed(Duration.zero);
    await dao.deleteSetlist(setlist.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSetlists.first, isNull);
    expect(emittedSetlists[1], isNotNull);
    _expectSetlistsEqual(emittedSetlists[1]!, setlist);
    expect(emittedSetlists.last, isNull);
  });

  test('watchAllSetlists emits on insert and delete', () async {
    final emittedSetlists = <List<Setlist>>[];
    final setlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );
    final subscription = dao.watchAllSetlists().listen(emittedSetlists.add);

    await Future<void>.delayed(Duration.zero);
    await dao.saveSetlist(setlist);
    await Future<void>.delayed(Duration.zero);
    await dao.deleteSetlist(setlist.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSetlists.first, isEmpty);
    expect(emittedSetlists[1].map((item) => item.id).toList(), ['setlist-1']);
    expect(emittedSetlists.last, isEmpty);
  });

  test('setlist items survive deleting the referenced song snapshot', () async {
    final song = Song(
      id: 'song-1',
      title: 'Intro',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
    );
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

    await database.songDao.saveSong(song);
    await dao.saveSetlist(setlist);
    await database.songDao.deleteSong(song.id);

    final loadedSetlist = await dao.getSetlistById(setlist.id);

    expect(loadedSetlist, isNotNull);
    _expectSetlistsEqual(loadedSetlist!, setlist);
  });
}

void _expectSetlistsEqual(Setlist actual, Setlist expected) {
  expect(actual.id, expected.id);
  expect(actual.title, expected.title);
  expect(actual.createdAt.isAtSameMomentAs(expected.createdAt), isTrue);
  expect(actual.items.length, expected.items.length);

  for (var itemIndex = 0; itemIndex < expected.items.length; itemIndex += 1) {
    final actualItem = actual.items[itemIndex];
    final expectedItem = expected.items[itemIndex];
    expect(actualItem.id, expectedItem.id);
    expect(actualItem.songId, expectedItem.songId);
    expect(actualItem.songTitle, expectedItem.songTitle);
    expect(actualItem.playbackEnabled, expectedItem.playbackEnabled);
    expect(actualItem.playAttachedAudio, expectedItem.playAttachedAudio);
    expect(
      actualItem.transitionSteps.length,
      expectedItem.transitionSteps.length,
    );

    for (var stepIndex = 0;
        stepIndex < expectedItem.transitionSteps.length;
        stepIndex += 1) {
      final actualStep = actualItem.transitionSteps[stepIndex];
      final expectedStep = expectedItem.transitionSteps[stepIndex];
      expect(actualStep.id, expectedStep.id);
      expect(actualStep.type, expectedStep.type);
      expect(actualStep.value, expectedStep.value);
      _expectAudioCueEqual(actualStep.audioCue, expectedStep.audioCue);
    }
  }
}

void _expectAudioCueEqual(AudioCue? actual, AudioCue? expected) {
  expect(actual == null, expected == null);
  if (actual == null || expected == null) {
    return;
  }

  expect(actual.type, expected.type);
  expect(actual.voiceText, expected.voiceText);
  expect(actual.voiceIdentifier, expected.voiceIdentifier);
  expect(actual.customFilePath, expected.customFilePath);
  expect(actual.customFileDisplayName, expected.customFileDisplayName);
  expect(actual.volumePercent, expected.volumePercent);
}
