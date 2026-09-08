import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/features/setlists/setlists_screen_controller.dart';

void main() {
  test('createSetlist saves a new empty setlist', () async {
    final repository = _CapturingSetlistRepository();
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(setlistsScreenControllerProvider)
        .createSetlist('Tour Set');

    expect(repository.savedSetlists, hasLength(1));
    final setlist = repository.savedSetlists.single;
    expect(setlist.title, 'Tour Set');
    expect(setlist.id, isNotEmpty);
    expect(setlist.items, isEmpty);
  });

  test('renameSetlist trims the new title defensively', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(setlistsScreenControllerProvider)
        .renameSetlist(original, '  Arena Set  ');

    expect(repository.savedSetlists, hasLength(1));
    final saved = repository.savedSetlists.single;
    expect(saved.id, original.id);
    expect(saved.title, 'Arena Set');
    expect(saved.items, original.items);
  });

  test('deleteSetlist delegates to the repository', () async {
    final repository = _CapturingSetlistRepository();
    await repository.saveSetlist(Setlist(
      id: 'setlist-9',
      title: 'Doomed',
      createdAt: DateTime(2024),
    ),);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(setlistsScreenControllerProvider)
        .deleteSetlist('setlist-9');

    expect(repository.deletedIds, ['setlist-9']);
  });

  test('addSongToSetlist appends a new setlist item for the selected song', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
        ),
      ],
    );
    final song = Song(
      id: 'song-2',
      title: 'Single',
      createdAt: DateTime(2024, 1, 2),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 1,
      endBar: 32,
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(setlistsScreenControllerProvider)
        .addSongToSetlist(original, song);

    expect(repository.savedSetlists, hasLength(1));
    final saved = repository.savedSetlists.single;
    expect(saved.items, hasLength(2));
    expect(saved.items.last.songId, song.id);
    expect(saved.items.last.songTitle, song.title);
    expect(saved.items.last.id, isNotEmpty);
  });

  test('moveSetlistItem moves an item to the requested position', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(id: 'item-1', songId: 'song-1', songTitle: 'Intro'),
        SetlistItem(id: 'item-2', songId: 'song-2', songTitle: 'Verse'),
        SetlistItem(id: 'item-3', songId: 'song-3', songTitle: 'Finale'),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    // Move first item to end (direct target index, no ReorderableListView
    // adjustment).
    await container.read(setlistsScreenControllerProvider).moveSetlistItem(
          original,
          oldIndex: 0,
          newIndex: 2,
        );

    expect(repository.savedSetlists, hasLength(1));
    final reordered = repository.savedSetlists.single;
    expect(
      reordered.items.map((item) => item.songTitle).toList(),
      ['Verse', 'Finale', 'Intro'],
    );
  });

  test('updateSetlistItemPlaybackFlags only updates the targeted item', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
        ),
        SetlistItem(
          id: 'item-2',
          songId: 'song-2',
          songTitle: 'Verse',
          playAttachedAudio: false,
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(setlistsScreenControllerProvider)
        .updateSetlistItemPlaybackFlags(
          original,
          itemId: 'item-2',
          playbackEnabled: false,
          playAttachedAudio: true,
        );

    expect(repository.savedSetlists, hasLength(1));
    final saved = repository.savedSetlists.single;
    expect(saved.items.first.playbackEnabled, isTrue);
    expect(saved.items.first.playAttachedAudio, isTrue);
    expect(saved.items.last.playbackEnabled, isFalse);
    expect(saved.items.last.playAttachedAudio, isTrue);
  });

  test('addTransitionStep appends a new transition step to the targeted item',
      () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);
    final step = container.read(setlistsScreenControllerProvider).createTransitionStep(
          type: SetlistTransitionStepType.countInBars,
          value: 2,
        );

    await container.read(setlistsScreenControllerProvider).addTransitionStep(
          original,
          itemId: 'item-1',
          step: step,
        );

    expect(repository.savedSetlists.single.items.single.transitionSteps, [step]);
  });

  test('updateTransitionStep replaces the matching transition step', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
          transitionSteps: [
            SetlistTransitionStep(
              id: 'step-1',
              type: SetlistTransitionStepType.pauseTimer,
              value: 5,
            ),
          ],
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container.read(setlistsScreenControllerProvider).updateTransitionStep(
          original,
          itemId: 'item-1',
          step: const SetlistTransitionStep(
            id: 'step-1',
            type: SetlistTransitionStepType.audio,
            value: 0,
            audioCue: AudioCue(
              type: AudioCueType.highPulse,
              volumePercent: 70,
            ),
          ),
        );

    final savedStep =
        repository.savedSetlists.single.items.single.transitionSteps.single;
    expect(savedStep.type, SetlistTransitionStepType.audio);
    expect(savedStep.audioCue?.type, AudioCueType.highPulse);
    expect(savedStep.audioCue?.volumePercent, 70);
  });

  test('removeTransitionStep drops the requested transition step', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
          transitionSteps: [
            SetlistTransitionStep(
              id: 'step-1',
              type: SetlistTransitionStepType.manual,
              value: 0,
            ),
            SetlistTransitionStep(
              id: 'step-2',
              type: SetlistTransitionStepType.countInBars,
              value: 2,
            ),
          ],
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container.read(setlistsScreenControllerProvider).removeTransitionStep(
          original,
          itemId: 'item-1',
          stepId: 'step-1',
        );

    expect(
      repository.savedSetlists.single.items.single.transitionSteps.map((step) => step.id),
      ['step-2'],
    );
  });

  test('reorderTransitionStep moves a transition step within the item', () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
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
              type: SetlistTransitionStepType.pauseTimer,
              value: 5,
            ),
          ],
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container.read(setlistsScreenControllerProvider).reorderTransitionStep(
          original,
          itemId: 'item-1',
          oldIndex: 0,
          newIndex: 1,
        );

    expect(
      repository.savedSetlists.single.items.single.transitionSteps.map((step) => step.id),
      ['step-2', 'step-1'],
    );
  });

  test('item updates use the latest stored setlist instead of a stale snapshot',
      () async {
    final original = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
        ),
      ],
    );
    final latest = Setlist(
      id: 'setlist-1',
      title: 'Warmup',
      createdAt: DateTime(2024, 1, 1),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
          playbackEnabled: false,
        ),
      ],
    );
    final repository = _CapturingSetlistRepository(initialSetlists: [original]);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await repository.saveSetlist(latest);
    repository.savedSetlists.clear();

    await container
        .read(setlistsScreenControllerProvider)
        .addTransitionStep(
          original,
          itemId: 'item-1',
          step: const SetlistTransitionStep(
            id: 'step-1',
            type: SetlistTransitionStepType.manual,
            value: 0,
          ),
        );

    final saved = repository.savedSetlists.single;
    expect(saved.items.single.playbackEnabled, isFalse);
    expect(saved.items.single.transitionSteps.single.id, 'step-1');
  });
}

ProviderContainer _createContainer(_CapturingSetlistRepository repository) {
  return ProviderContainer(
    overrides: [
      setlistRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _CapturingSetlistRepository implements SetlistRepository {
  _CapturingSetlistRepository({List<Setlist> initialSetlists = const []}) {
    for (final setlist in initialSetlists) {
      _storedSetlists[setlist.id] = setlist;
    }
  }

  final List<Setlist> savedSetlists = [];
  final List<String> deletedIds = [];
  final Map<String, Setlist> _storedSetlists = {};

  @override
  Future<void> deleteSetlist(String setlistId) async => deletedIds.add(setlistId);

  @override
  Future<List<Setlist>> getAllSetlists() async => [];

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => _storedSetlists[setlistId];

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    final setlist = _storedSetlists[setlistId];
    if (setlist == null) {
      throw StateError('Setlist not found: $setlistId');
    }

    return setlist;
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {
    _storedSetlists[setlist.id] = setlist;
    savedSetlists.add(setlist);
  }

  @override
  Stream<List<Setlist>> watchAllSetlists() => const Stream.empty();

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) => const Stream.empty();
}
