import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/audio_cue.dart';
import '../../core/domain/song.dart';
import '../../core/domain/setlist.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/service_providers.dart';

final setlistsScreenControllerProvider = Provider(
  (ref) => SetlistsScreenController(ref),
);

class SetlistsScreenController {
  SetlistsScreenController(this._ref);

  static final _logger = Logger('SetlistsScreenController');

  final Ref _ref;
  final _uuid = const Uuid();

  Future<void> createSetlist(String title) async {
    await _ref.read(setlistRepositoryProvider).saveSetlist(
          Setlist(
            id: _uuid.v4(),
            title: title.trim(),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> renameSetlist(Setlist setlist, String newTitle) async {
    final latestSetlist = await _loadLatestSetlist(setlist.id);
    await _ref.read(setlistRepositoryProvider).saveSetlist(
          latestSetlist.copyWith(title: newTitle.trim()),
        );
  }

  Future<void> deleteSetlist(String setlistId) async {
    final repo = _ref.read(setlistRepositoryProvider);
    final setlist = await repo.loadSetlist(setlistId);

    await repo.deleteSetlist(setlistId);

    _cleanupSetlistCustomFiles(setlist);
  }

  Future<void> addSongToSetlist(Setlist setlist, Song song) async {
    final latestSetlist = await _loadLatestSetlist(setlist.id);
    final updatedItems = [
      ...latestSetlist.items,
      SetlistItem(
        id: _uuid.v4(),
        songId: song.id,
        songTitle: song.title,
      ),
    ];

    await _ref.read(setlistRepositoryProvider).saveSetlist(
          latestSetlist.copyWith(items: updatedItems),
        );
  }

  Future<void> moveSetlistItem(
    Setlist setlist, {
    required int oldIndex,
    required int newIndex,
  }) async {
    final latestSetlist = await _loadLatestSetlist(setlist.id);
    final reorderedItems = List.of(latestSetlist.items);
    final movedItem = reorderedItems.removeAt(oldIndex);
    reorderedItems.insert(newIndex, movedItem);

    await _ref.read(setlistRepositoryProvider).saveSetlist(
          latestSetlist.copyWith(items: reorderedItems),
        );
  }

  Future<void> updateSetlistItemPlaybackFlags(
    Setlist setlist, {
    required String itemId,
    bool? playbackEnabled,
    bool? playAttachedAudio,
  }) async {
    await _saveUpdatedItem(
      setlist,
      itemId: itemId,
      update: (item) => item.copyWith(
        playbackEnabled: playbackEnabled,
        playAttachedAudio: playAttachedAudio,
      ),
    );
  }

  SetlistTransitionStep createTransitionStep({
    required SetlistTransitionStepType type,
    required int value,
    AudioCue? audioCue,
  }) {
    return SetlistTransitionStep(
      id: _uuid.v4(),
      type: type,
      value: value,
      audioCue: audioCue,
    );
  }

  Future<void> addTransitionStep(
    Setlist setlist, {
    required String itemId,
    required SetlistTransitionStep step,
  }) async {
    await _saveUpdatedItem(
      setlist,
      itemId: itemId,
      update: (item) => item.copyWith(
        transitionSteps: [...item.transitionSteps, step],
      ),
    );
  }

  Future<void> updateTransitionStep(
    Setlist setlist, {
    required String itemId,
    required SetlistTransitionStep step,
  }) async {
    await _saveUpdatedItem(
      setlist,
      itemId: itemId,
      update: (item) => item.copyWith(
        transitionSteps: item.transitionSteps
            .map((existingStep) => existingStep.id == step.id ? step : existingStep)
            .toList(growable: false),
      ),
    );
  }

  Future<void> removeTransitionStep(
    Setlist setlist, {
    required String itemId,
    required String stepId,
  }) async {
    // Find the step being removed to clean up its custom file.
    final item = setlist.items.where((i) => i.id == itemId).firstOrNull;
    final removedStep = item?.transitionSteps
        .where((s) => s.id == stepId)
        .firstOrNull;

    await _saveUpdatedItem(
      setlist,
      itemId: itemId,
      update: (item) => item.copyWith(
        transitionSteps: item.transitionSteps
            .where((step) => step.id != stepId)
            .toList(growable: false),
      ),
    );

    _cleanupStepCustomFile(removedStep);
  }

  Future<void> reorderTransitionStep(
    Setlist setlist, {
    required String itemId,
    required int oldIndex,
    required int newIndex,
  }) async {
    await _saveUpdatedItem(
      setlist,
      itemId: itemId,
      update: (item) {
        final reorderedSteps = List.of(item.transitionSteps);
        final movedStep = reorderedSteps.removeAt(oldIndex);
        reorderedSteps.insert(newIndex, movedStep);
        return item.copyWith(transitionSteps: reorderedSteps);
      },
    );
  }

  Future<void> _saveUpdatedItem(
    Setlist setlist, {
    required String itemId,
    required SetlistItem Function(SetlistItem item) update,
  }) async {
    final latestSetlist = await _loadLatestSetlist(setlist.id);
    var itemWasUpdated = false;
    final updatedItems = latestSetlist.items
        .map((item) {
          if (item.id != itemId) {
            return item;
          }
          itemWasUpdated = true;
          return update(item);
        })
        .toList(growable: false);
    if (!itemWasUpdated) {
      throw StateError('Setlist item not found: $itemId');
    }

    await _ref.read(setlistRepositoryProvider).saveSetlist(
          latestSetlist.copyWith(items: updatedItems),
        );
  }

  Future<Setlist> _loadLatestSetlist(String setlistId) {
    return _ref.read(setlistRepositoryProvider).loadSetlist(setlistId);
  }

  void _cleanupSetlistCustomFiles(Setlist setlist) {
    for (final item in setlist.items) {
      for (final step in item.transitionSteps) {
        _cleanupStepCustomFile(step);
      }
    }
  }

  void _cleanupStepCustomFile(SetlistTransitionStep? step) {
    final path = step?.audioCue?.customFilePath;
    if (path == null || path.isEmpty) return;

    final storage = _ref.read(linkedAudioFileStorageProvider);
    storage.deleteFromStorage(path).catchError((Object error) {
      _logger.warning(
        'Failed to delete custom cue file on transition step cleanup.',
        error,
      );
    });
  }
}
