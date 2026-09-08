import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/core/widgets/td_toggle.dart';
import 'package:tempodeck/features/setlists/setlist_editor_screen.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('moves setlist item down via arrow button', (tester) async {
    final repository = _RecordingSetlistRepository(setlist: _setlist);
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the "Move down" arrow on the first item ("Intro").
    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    expect(
      repository.savedSetlists.single.items.map((item) => item.songTitle).toList(),
      ['Verse', 'Intro', 'Finale'],
    );
  });

  testWidgets('shows the current setlist title in the app bar', (tester) async {
    final repository = _RecordingSetlistRepository(setlist: _setlist);
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Tour Set'), findsOneWidget);
  });

  testWidgets('shows empty state when a setlist has no items', (tester) async {
    final repository = _RecordingSetlistRepository(
      setlist: Setlist(
        id: 'setlist-1',
        title: 'Empty',
        createdAt: DateTime(2024, 1, 1),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No songs in this setlist yet'), findsOneWidget);
  });

  testWidgets('toggles item playback flags and persists the updated setlist',
      (tester) async {
    final repository = _RecordingSetlistRepository(setlist: _setlist);
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TDToggle).first);
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    expect(repository.savedSetlists.single.items.first.playbackEnabled, isFalse);
    expect(repository.savedSetlists.single.items.first.playAttachedAudio, isTrue);

    await tester.tap(find.byType(TDToggle).at(1));
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(2));
    expect(repository.savedSetlists.last.items.first.playbackEnabled, isFalse);
    expect(repository.savedSetlists.last.items.first.playAttachedAudio, isFalse);
  });

  testWidgets('adds a transition step and persists it', (tester) async {
    final repository = _RecordingSetlistRepository(setlist: _setlist);
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    final step = repository.savedSetlists.single.items.first.transitionSteps.single;
    expect(step.type, SetlistTransitionStepType.countInBars);
    expect(step.value, 2);
  });

  testWidgets('edits an existing transition step and persists it', (tester) async {
    final repository = _RecordingSetlistRepository(
      setlist: Setlist(
        id: 'setlist-1',
        title: 'Tour Set',
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
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit step'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<SetlistTransitionStepType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio cue').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final step = repository.savedSetlists.single.items.single.transitionSteps.single;
    expect(step.id, 'step-1');
    expect(step.type, SetlistTransitionStepType.audio);
    expect(step.audioCue?.type, AudioCueType.highPulse);
    expect(step.audioCue?.volumePercent, 100);
  });

  testWidgets('reorders and deletes transition steps', (tester) async {
    final repository = _RecordingSetlistRepository(
      setlist: Setlist(
        id: 'setlist-1',
        title: 'Tour Set',
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
                type: SetlistTransitionStepType.manual,
                value: 0,
              ),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        setlistRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(repository.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SetlistEditorScreen(setlistId: 'setlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Move step down').first);
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    expect(
      repository.savedSetlists.single.items.single.transitionSteps.map((step) => step.id),
      ['step-2', 'step-1'],
    );

    await tester.tap(find.byTooltip('Delete step').first);
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(2));
    expect(
      repository.savedSetlists.last.items.single.transitionSteps.map((step) => step.id),
      ['step-1'],
    );
  });
}

final _setlist = Setlist(
  id: 'setlist-1',
  title: 'Tour Set',
  createdAt: DateTime(2024, 1, 1),
  items: const [
    SetlistItem(id: 'item-1', songId: 'song-1', songTitle: 'Intro'),
    SetlistItem(id: 'item-2', songId: 'song-2', songTitle: 'Verse'),
    SetlistItem(id: 'item-3', songId: 'song-3', songTitle: 'Finale'),
  ],
);

class _RecordingSetlistRepository implements SetlistRepository {
  _RecordingSetlistRepository({required Setlist setlist}) : _setlist = setlist {
    _controller = StreamController<Setlist?>.broadcast();
  }

  late final StreamController<Setlist?> _controller;
  Setlist _setlist;
  final List<Setlist> savedSetlists = [];

  Future<void> dispose() => _controller.close();

  @override
  Future<void> deleteSetlist(String setlistId) => throw UnimplementedError();

  @override
  Future<List<Setlist>> getAllSetlists() => throw UnimplementedError();

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => _setlist;

  @override
  Future<Setlist> loadSetlist(String setlistId) async => _setlist;

  @override
  Future<void> saveSetlist(Setlist setlist) async {
    _setlist = setlist;
    savedSetlists.add(setlist);
    _controller.add(_setlist);
  }

  @override
  Stream<List<Setlist>> watchAllSetlists() => throw UnimplementedError();

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) async* {
    yield _setlist;
    yield* _controller.stream;
  }
}
