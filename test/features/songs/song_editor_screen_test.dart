import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/audio_mixer_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/audio/i_audio_engine.dart';
import 'package:tempodeck/core/audio/text_to_speech_client.dart';
import 'package:tempodeck/core/audio/linked_audio_export_augmenter.dart';
import 'package:tempodeck/core/files/linked_audio_import_service.dart';
import 'package:tempodeck/core/files/linked_audio_path_repair_service.dart';
import 'package:tempodeck/core/files/linked_audio_picker.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/features/songs/song_editor_screen.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('shows song basic settings from repository', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('songEditorTitleField')), findsOneWidget);
    expect(find.text('Editable Song'), findsOneWidget);
    expect(find.text('128'), findsWidgets);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('Bars 12-40'), findsOneWidget);
  });

  testWidgets('saves edited basic settings', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('songEditorTitleField')),
      'Updated Song',
    );
    await tester.enterText(
      find.byKey(const Key('songEditorBpmField')),
      '24',
    );
    await tester.pump();
    await _selectDropdownCardOption(
      tester,
      const Key('songEditorBeatsPerBarField'),
      '5',
    );
    await _selectDropdownCardOption(
      tester,
      const Key('songEditorBeatUnitField'),
      '8',
    );
    await tester.enterText(
      find.byKey(const Key('songEditorCountInBarsField')),
      '4',
    );
    await tester.enterText(
      find.byKey(const Key('songEditorEndBarField')),
      '64',
    );

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs, isNotEmpty);
    final saved = repository.savedSongs.last;
    expect(saved.title, 'Updated Song');
    expect(saved.startBpm, 24);
    expect(saved.beatsPerBar, 5);
    expect(saved.beatUnit, 8);
    expect(saved.countInBars, 4);
    expect(saved.endBar, 64);
    expect(saved.tempoChanges, _testSong.tempoChanges);
    expect(saved.loops, _testSong.loops);
    expect(saved.songEvents, _testSong.songEvents);
    expect(saved.beatPatterns, _testSong.beatPatterns);
    expect(saved.linkedAudio, isNotNull);
    expect(saved.linkedAudio!.filePath, '/tmp/test-track.mp3');
    expect(saved.linkedAudio!.displayName, 'Test Track');
    expect(saved.linkedAudio!.offsetMilliseconds, 1000);
    expect(saved.linkedAudio!.volumePercent, 80);
    expect(saved.linkedAudio!.playInLiveMode, isTrue);

  });

  testWidgets('bpm stepper buttons increment and decrement by one',
      (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    // Default BPM from _testSong is 128.
    expect(find.text('128'), findsWidgets);

    await tester.tap(find.byKey(const Key('bpm-increment')));
    await tester.pump();
    expect(find.text('129'), findsWidgets);

    await tester.tap(find.byKey(const Key('bpm-decrement')));
    await tester.pump();
    expect(find.text('128'), findsWidgets);

    // Trigger auto-save to verify the change persists.
    await tester.tap(find.byKey(const Key('bpm-increment')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs, isNotEmpty);
    expect(repository.savedSongs.last.startBpm, 129);
  });

  testWidgets('adds a tempo change and shows it in the tempo map', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songEditorAddTempoChangeButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tempoChangeBarIndexField')), '24');
    await tester.enterText(
      find.byKey(const Key('tempoChangeBpmField')),
      '126',
    );
    await tester.pump();
    await _selectDropdownCardOption(
      tester,
      const Key('tempoChangeBeatsPerBarField'),
      '5',
    );
    await _selectDropdownCardOption(
      tester,
      const Key('tempoChangeBeatUnitField'),
      '8',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Bar 24'), findsWidgets);
    expect(find.text('Bars 24-40'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.tempoChanges, hasLength(2));
    expect(repository.savedSongs.last.tempoChanges.last.barIndex, 24);
  });

  testWidgets('edits an existing tempo change', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('tempoMapSegmentTile-12')),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('tempoChangeBpmField')),
      '128',
    );
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('128 BPM · 4/4'), findsWidgets);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.tempoChanges.single.bpm, 128);
    expect(repository.savedSongs.last.tempoChanges.single.id, 'tempo-1');
  });

  testWidgets('shows not found state when song is missing', (tester) async {
    final repository = _EditableSongRepository(song: null);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    expect(find.text('Song not found'), findsOneWidget);
  });

  testWidgets('adds a loop and saves it', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songEditorAddLoopButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('songLoopStartBarField')), '20');
    await tester.enterText(find.byKey(const Key('songLoopEndBarField')), '24');
    await tester.enterText(find.byKey(const Key('songLoopRepeatCountField')), '3');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Bars 20-24'), findsOneWidget);
    expect(find.text('3 repeats'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.loops, hasLength(2));
    expect(repository.savedSongs.last.loops.last.startBar, 20);
  });

  testWidgets('edits an existing loop', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('songLoopTile-loop-1')),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('songLoopRepeatCountField')), '4');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('4 repeats'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.loops.single.repeatCount, 4);
    expect(repository.savedSongs.last.loops.single.id, 'loop-1');
  });

  testWidgets('adds alternative endings with nested content and saves them', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songEditorAddLoopButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('songLoopStartBarField')), '20');
    await tester.enterText(find.byKey(const Key('songLoopEndBarField')), '24');
    await tester.enterText(find.byKey(const Key('songLoopRepeatCountField')), '2');
    await tester.tap(find.byKey(const Key('songLoopAlternativeEndingToggle-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('songLoopAlternativeEndingLength-2')),
      '2',
    );
    await tester.tap(
      find.byKey(const Key('songLoopAlternativeEndingAddTempoChange-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tempoChangeBarIndexField')), '2');
    await tester.tap(find.byKey(const Key('tempoChangeBeatsPerBarField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('songLoopAlternativeEndingAddSongEvent-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('songEventBarIndexField')), '2');
    await tester.enterText(find.byKey(const Key('songEventLabelField')), 'Ending cue');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('songLoopAlternativeEndingAddBeatPattern-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('songBeatPatternBarIndexField')),
      '2',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    final savedLoop = repository.savedSongs.last.loops.last;
    expect(savedLoop.alternativeEndings, hasLength(1));
    expect(savedLoop.alternativeEndings.single.repeatPass, 2);
    expect(savedLoop.alternativeEndings.single.lengthBars, 2);
    expect(savedLoop.alternativeEndings.single.tempoChanges, hasLength(1));
    expect(savedLoop.alternativeEndings.single.tempoChanges.single.barIndex, 2);
    expect(savedLoop.alternativeEndings.single.tempoChanges.single.beatsPerBar, 3);
    expect(savedLoop.alternativeEndings.single.songEvents, hasLength(1));
    expect(savedLoop.alternativeEndings.single.songEvents.single.label, 'Ending cue');
    expect(savedLoop.alternativeEndings.single.beatPatterns, hasLength(1));
    expect(savedLoop.alternativeEndings.single.beatPatterns.single.barIndex, 2);
  });

  testWidgets('adds a song event and saves it', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songEditorAddSongEventButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('songEventBarIndexField')), '28');
    await tester.enterText(find.byKey(const Key('songEventLabelField')), 'Bridge');
    await tester.tap(find.byKey(const Key('songEventAudioCueTypeField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('songEventBarsBeforeField')), '3');
    await tester.enterText(find.byKey(const Key('songEventVoiceTextField')), 'Bridge next');

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Bridge · Bar 28'), findsOneWidget);
    expect(find.text('Voice · 3 bars before'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.songEvents, hasLength(2));
    expect(repository.savedSongs.last.songEvents.last.label, 'Bridge');
    expect(repository.savedSongs.last.songEvents.last.audioCue!.type, AudioCueType.voice);
  });

  testWidgets('edits an existing song event', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('songEventTile-event-1')),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('songEventLabelField')), 'Final Chorus');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Final Chorus · Bar 24'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.songEvents.single.label, 'Final Chorus');
    expect(repository.savedSongs.last.songEvents.single.id, 'event-1');
  });

  testWidgets('adds a beat pattern and saves it', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('songEditorAddBeatPatternButton')),
    );
    await tester.tap(find.byKey(const Key('songEditorAddBeatPatternButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('songBeatPatternBarIndexField')),
      '30',
    );
    await tester.enterText(
      find.byKey(const Key('songBeatPatternRepeatPassField')),
      '2',
    );
    await tester.tap(find.byKey(const Key('songBeatPatternSubdivisionField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('songBeatPatternAccentChip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('songBeatPatternAccentChip-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Bar 30'), findsWidgets);
    expect(find.textContaining('+2 subdivision'), findsOneWidget);
    expect(find.textContaining('Pass 2'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.beatPatterns, hasLength(2));
    expect(repository.savedSongs.last.beatPatterns.last.barIndex, 30);
    expect(
      repository.savedSongs.last.beatPatterns.last.subdivision,
      Subdivision.three,
    );
    expect(
      repository.savedSongs.last.beatPatterns.last.repeatPass,
      2,
    );
  });

  testWidgets('edits an existing beat pattern', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('songBeatPatternTile-pattern-1')),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('songBeatPatternTile-pattern-1')),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songBeatPatternAccentChip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('+1 subdivision \u00B7 H L L'), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.beatPatterns.single.id, 'pattern-1');
    expect(
      repository.savedSongs.last.beatPatterns.single.accents,
      const [AccentLevel.high, AccentLevel.low, AccentLevel.low],
    );
  });

  testWidgets('attaches linked audio to a song without one', (tester) async {
    final repository = _EditableSongRepository(
      song: _testSong.copyWith(clearLinkedAudio: true),
    );
    final picker = _FakeLinkedAudioPicker(
      pickedFile: const PickedLinkedAudioFile(
        filePath: '/tmp/new-track.mp3',
        displayName: 'New Track',
      ),
    );
    const importedPath = '/app/support/linked_audio/imported-track.mp3';
    final container = _createContainer(
      repository,
      picker: picker,
      importer: _FakeLinkedAudioImportService(importedPath: importedPath),
      audioEngine: _FakeAudioEngine(),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final attachButton = find.byKey(const Key('songEditorAttachLinkedAudioButton'));
    await _scrollUntilVisible(tester, attachButton);
    await tester.tap(attachButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('songLinkedAudioDisplayNameText')), findsOneWidget);
    expect(find.byKey(const Key('songLinkedAudioFilePathText')), findsNothing);
    expect(find.textContaining('Offset 0ms'), findsOneWidget);
    expect(find.textContaining('Live playback Enabled'), findsOneWidget);
    expect(find.byKey(const Key('songLinkedAudioWaveformCursor')), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.linkedAudio, isNotNull);
    expect(
      repository.savedSongs.last.linkedAudio!.filePath,
      importedPath,
    );
    expect(repository.savedSongs.last.linkedAudio!.offsetMilliseconds, 0);
    expect(repository.savedSongs.last.linkedAudio!.volumePercent, 100);
    expect(repository.savedSongs.last.linkedAudio!.playInLiveMode, isTrue);
  });

  testWidgets('replaces linked audio file and saves it', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final picker = _FakeLinkedAudioPicker(
      pickedFile: const PickedLinkedAudioFile(
        filePath: '/tmp/new-track.mp3',
        displayName: 'New Track',
      ),
    );
    const importedPath = '/app/support/linked_audio/replaced-track.mp3';
    final container = _createContainer(
      repository,
      picker: picker,
      importer: _FakeLinkedAudioImportService(importedPath: importedPath),
      audioEngine: _FakeAudioEngine(),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final replaceButton =
        find.byKey(const Key('songEditorReplaceLinkedAudioButton'));
    await _scrollUntilVisible(tester, replaceButton);
    await tester.tap(replaceButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('songLinkedAudioDisplayNameText')), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.linkedAudio, isNotNull);
    expect(
      repository.savedSongs.last.linkedAudio!.filePath,
      importedPath,
    );
  });

  testWidgets('preloads replaced linked audio in the editor', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final audioEngine = _FakeAudioEngine();
    final picker = _FakeLinkedAudioPicker(
      pickedFile: const PickedLinkedAudioFile(
        filePath: '/tmp/new-track.mp3',
        displayName: 'New Track',
      ),
    );
    const importedPath = '/app/support/linked_audio/replaced-track.mp3';
    final container = _createContainer(
      repository,
      picker: picker,
      importer: _FakeLinkedAudioImportService(importedPath: importedPath),
      audioEngine: audioEngine,
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final replaceButton =
        find.byKey(const Key('songEditorReplaceLinkedAudioButton'));
    await _scrollUntilVisible(tester, replaceButton);
    await tester.tap(replaceButton);
    await tester.pumpAndSettle();

    expect(
      audioEngine.preloadedLinkedAudioPaths,
      containsAll(['/tmp/test-track.mp3', importedPath]),
    );
  });

  testWidgets('edits linked audio inline and previews with song mixer volume',
      (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final audioEngine = _FakeAudioEngine();
    final container = _createContainer(
      repository,
      picker: _FakeLinkedAudioPicker(),
      audioEngine: audioEngine,
    );
    addTearDown(container.dispose);
    container.read(audioMixerControllerProvider.notifier).setSongVolumePercent(
          65,
        );

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    expect(audioEngine.preloadedLinkedAudioPaths, ['/tmp/test-track.mp3']);

    await tester.enterText(
      find.byKey(const Key('songLinkedAudioOffsetField')),
      '2500',
    );
    await tester.pumpAndSettle();

    final liveModeSwitch =
        find.byKey(const Key('songLinkedAudioPlayInLiveModeSwitch'));
    await _scrollUntilVisible(tester, liveModeSwitch);
    await tester.tap(liveModeSwitch);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('songLinkedAudioDisplayNameText')), findsOneWidget);
    expect(find.textContaining('Offset 2500ms'), findsOneWidget);

    final previewButton = find.byKey(const Key('songLinkedAudioPreviewButton'));
    await _scrollUntilVisible(tester, previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(audioEngine.playedLinkedAudioPaths, ['/tmp/test-track.mp3']);
    expect(audioEngine.playedLinkedAudioOffsets, [const Duration(milliseconds: 2500)]);
    expect(audioEngine.playedLinkedAudioVolumes.single, closeTo(0.65, 0.001));

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.linkedAudio!.displayName, 'Test Track');
    expect(repository.savedSongs.last.linkedAudio!.offsetMilliseconds, 2500);
    expect(repository.savedSongs.last.linkedAudio!.playInLiveMode, isFalse);
  });

  testWidgets('stops and restarts linked audio preview with the latest offset',
      (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final audioEngine = _FakeAudioEngine();
    final container = _createContainer(
      repository,
      picker: _FakeLinkedAudioPicker(),
      audioEngine: audioEngine,
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final previewButton = find.byKey(const Key('songLinkedAudioPreviewButton'));
    await _scrollUntilVisible(tester, previewButton);

    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(audioEngine.playedLinkedAudioPaths, ['/tmp/test-track.mp3']);
    expect(audioEngine.stopCallCount, 1);
    expect(
      audioEngine.playedLinkedAudioOffsets,
      [const Duration(milliseconds: 1000)],
    );

    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(audioEngine.stopCallCount, 2);

    await tester.enterText(
      find.byKey(const Key('songLinkedAudioOffsetField')),
      '2003',
    );
    await tester.pumpAndSettle();

    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(
      audioEngine.playedLinkedAudioOffsets,
      [
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 2003),
      ],
    );
    expect(audioEngine.stopCallCount, 3);
  });

  testWidgets(
      'awaits linked audio stop before restarting preview with a new offset',
      (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final audioEngine = _DelayedStopAudioEngine();
    final container = _createContainer(
      repository,
      picker: _FakeLinkedAudioPicker(),
      audioEngine: audioEngine,
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final previewButton = find.byKey(const Key('songLinkedAudioPreviewButton'));
    await _scrollUntilVisible(tester, previewButton);

    await tester.tap(previewButton);
    await tester.pump();
    expect(audioEngine.playedLinkedAudioOffsets, isEmpty);

    audioEngine.completePendingStop();
    await tester.pumpAndSettle();
    expect(
      audioEngine.playedLinkedAudioOffsets,
      [const Duration(milliseconds: 1000)],
    );

    await tester.enterText(
      find.byKey(const Key('songLinkedAudioOffsetField')),
      '2003',
    );
    await tester.pump();

    await tester.tap(previewButton);
    await tester.pump();
    expect(audioEngine.stopCallCount, 2);

    audioEngine.completePendingStop();
    await tester.pumpAndSettle();

    await tester.tap(previewButton);
    await tester.pump();
    expect(
      audioEngine.playedLinkedAudioOffsets,
      [const Duration(milliseconds: 1000)],
    );

    audioEngine.completePendingStop();
    await tester.pumpAndSettle();

    expect(
      audioEngine.playedLinkedAudioOffsets,
      [
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 2003),
      ],
    );
  });

  testWidgets('repairs stale linked audio paths before preview and save',
      (tester) async {
    final repository = _EditableSongRepository(
      song: _testSong.copyWith(
        linkedAudio: const LinkedAudioFile(
          filePath: '/old/container/tmp/echoes.mp3',
          displayName: 'echoes.mp3',
          offsetMilliseconds: 2003,
          volumePercent: 100,
        ),
      ),
    );
    final audioEngine = _FakeAudioEngine();
    const repairedPath = '/documents/echoes.mp3';
    final container = _createContainer(
      repository,
      audioEngine: audioEngine,
      pathRepairService: const _FakeLinkedAudioPathRepairService(
        repairedPath: repairedPath,
      ),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final previewButton = find.byKey(const Key('songLinkedAudioPreviewButton'));
    await _scrollUntilVisible(tester, previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(audioEngine.playedLinkedAudioPaths.single, repairedPath);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.savedSongs.last.linkedAudio!.filePath, repairedPath);
  });

  testWidgets('updates linked audio offset only through waveform dragging relative to the center cursor',
      (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(
      repository,
      picker: _FakeLinkedAudioPicker(),
      audioEngine: _FakeAudioEngine(),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final waveform = find.byKey(const Key('songLinkedAudioWaveformEditor'));
    await _scrollUntilVisible(tester, waveform);
    final waveformRect = tester.getRect(waveform);
    await tester.tapAt(waveformRect.center);
    await tester.pumpAndSettle();
    await tester.dragFrom(
      Offset(
        waveformRect.left + waveformRect.width * 0.15,
        waveformRect.center.dy,
      ),
      Offset(
        waveformRect.width * 0.65,
        0,
      ),
    );
    await tester.pumpAndSettle();

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      repository.savedSongs.last.linkedAudio!.offsetMilliseconds,
      inInclusiveRange(1370, 1450),
    );
  });

  testWidgets('removes linked audio and saves it', (tester) async {
    final repository = _EditableSongRepository(song: _testSong);
    final container = _createContainer(
      repository,
      picker: _FakeLinkedAudioPicker(),
      audioEngine: _FakeAudioEngine(),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);
    await tester.pumpAndSettle();

    final removeButton = find.byKey(const Key('songEditorRemoveLinkedAudioButton'));
    await _scrollUntilVisible(tester, removeButton);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    final attachButton = find.byKey(const Key('songEditorAttachLinkedAudioButton'));
    await _scrollUntilVisible(tester, attachButton);
    expect(find.byKey(const Key('songEditorAttachLinkedAudioButton')), findsOneWidget);

    // Trigger debounced auto-save.
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.savedSongs, isNotEmpty);

    expect(repository.savedSongs.last.linkedAudio, isNull);
  });
}

ProviderContainer _createContainer(
  _EditableSongRepository repository, {
  _FakeLinkedAudioPicker? picker,
  _FakeLinkedAudioImportService? importer,
  _FakeLinkedAudioPathRepairService? pathRepairService,
  _FakeAudioEngine? audioEngine,
  LinkedAudioClipLoader? linkedAudioClipLoader,
}) {
  return ProviderContainer(
    overrides: [
      appVariantProvider.overrideWithValue(AppVariant.mobile),
      songRepositoryProvider.overrideWithValue(repository),
      linkedAudioPickerProvider.overrideWithValue(
        picker ?? _FakeLinkedAudioPicker(),
      ),
      linkedAudioImportServiceProvider.overrideWithValue(
        importer ?? _FakeLinkedAudioImportService(),
      ),
      linkedAudioPathRepairServiceProvider.overrideWithValue(
        pathRepairService ?? const _FakeLinkedAudioPathRepairService(),
      ),
      audioEngineProvider.overrideWithValue(
        audioEngine ?? _FakeAudioEngine(),
      ),
      linkedAudioClipLoaderProvider.overrideWithValue(
        linkedAudioClipLoader ?? _FakeLinkedAudioClipLoader(),
      ),
    ],
  );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_SongEditorHarness(container: container));
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _selectDropdownCardOption(
  WidgetTester tester,
  Key dropdownKey,
  String optionLabel,
) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();

  final optionFinder = find.text(optionLabel);
  final scrollableFinder = find.byType(Scrollable).last;
  for (var attempt = 0; attempt < 20 && optionFinder.evaluate().isEmpty; attempt += 1) {
    await tester.drag(scrollableFinder, const Offset(0, -300));
    await tester.pumpAndSettle();
  }

  await tester.tap(optionFinder.last);
  await tester.pumpAndSettle();
}

class _SongEditorHarness extends StatelessWidget {
  const _SongEditorHarness({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SongEditorScreen(songId: 'song-1'),
      ),
    );
  }
}

final _testSong = Song(
  id: 'song-1',
  title: 'Editable Song',
  createdAt: DateTime(2024, 1, 1),
  startBpm: 128,
  beatsPerBar: 7,
  beatUnit: 4,
  countInBars: 3,
  endBar: 40,
  tempoChanges: const [
    SongTempoChange(
      id: 'tempo-1',
      barIndex: 12,
      bpm: 144,
      beatsPerBar: 4,
      beatUnit: 4,
    ),
  ],
  loops: const [
    SongLoop(
      id: 'loop-1',
      startBar: 16,
      endBar: 20,
      repeatCount: 2,
    ),
  ],
  songEvents: const [
    SongEvent(
      id: 'event-1',
      barIndex: 24,
      label: 'Chorus',
      audioCue: AudioCue(
        type: AudioCueType.highPulse,
        volumePercent: 90,
      ),
      audioCueBarsBefore: 1,
    ),
  ],
  beatPatterns: const [
    SongBarBeatPattern(
      id: 'pattern-1',
      barIndex: 18,
      accents: [AccentLevel.high, AccentLevel.normal, AccentLevel.low],
      subdivision: Subdivision.two,
    ),
  ],
  linkedAudio: const LinkedAudioFile(
    filePath: '/tmp/test-track.mp3',
    displayName: 'Test Track',
    offsetMilliseconds: 1000,
    volumePercent: 80,
  ),
);

class _FakeLinkedAudioPicker implements LinkedAudioPicker {
  _FakeLinkedAudioPicker({this.pickedFile});

  final PickedLinkedAudioFile? pickedFile;

  @override
  Future<PickedLinkedAudioFile?> pickAudioFile() async => pickedFile;
}

class _FakeLinkedAudioImportService implements LinkedAudioImportService {
  _FakeLinkedAudioImportService({this.importedPath});

  final String? importedPath;

  @override
  Future<PickedLinkedAudioFile> importPickedAudioFile(
    PickedLinkedAudioFile pickedFile,
  ) async {
    return PickedLinkedAudioFile(
      filePath: importedPath ?? pickedFile.filePath,
      displayName: pickedFile.displayName,
    );
  }
}

class _FakeLinkedAudioPathRepairService implements LinkedAudioPathRepairService {
  const _FakeLinkedAudioPathRepairService({this.repairedPath});

  final String? repairedPath;

  @override
  Future<LinkedAudioFile> repairIfNeeded(LinkedAudioFile linkedAudioFile) async {
    if (repairedPath == null) {
      return linkedAudioFile;
    }

    return LinkedAudioFile(
      filePath: repairedPath!,
      displayName: linkedAudioFile.displayName,
      offsetMilliseconds: linkedAudioFile.offsetMilliseconds,
      volumePercent: linkedAudioFile.volumePercent,
      playInLiveMode: linkedAudioFile.playInLiveMode,
    );
  }
}

class _FakeAudioEngine implements IAudioEngine {
  final List<String> preloadedLinkedAudioPaths = [];
  final List<String> playedLinkedAudioPaths = [];
  final List<Duration> playedLinkedAudioOffsets = [];
  final List<double> playedLinkedAudioVolumes = [];
  int stopCallCount = 0;

  @override
  bool get isInitialized => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadClickSoundSet(ClickSoundSet set) async {}

  @override
  Future<void> playCue(AudioCue cue) async {}

  @override
  Future<void> preloadLinkedAudio(String filePath) async {
    preloadedLinkedAudioPaths.add(filePath);
  }

  @override
  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async => const PreparedLinkedAudioHandle('song-editor-test');

  @override
  Future<void> playPreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {}

  @override
  Future<void> releasePreparedLinkedAudio(
    PreparedLinkedAudioHandle handle,
  ) async {}

  @override
  void playClick(AccentLevel accent) {}

  @override
  void playSubdivisionClick() {}

  @override
  Future<void> playLinkedAudio(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {
    playedLinkedAudioPaths.add(filePath);
    playedLinkedAudioOffsets.add(offset);
    playedLinkedAudioVolumes.add(volume);
  }

  @override
  void selectClickSoundSet(ClickSoundSet set) {}

  @override
  void setClickChannelVolume(ClickSoundVariant variant, double volume) {}

  @override
  void setLimiter(AudioLimiterSettings settings) {}

  @override
  void setMasterVolume(double volume) {}

  @override
  Future<List<TextToSpeechVoice>> getAvailableVoices() async => [];

  @override
  Future<void> speakCue(String text, {String? voiceIdentifier}) async {}

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }
}

class _DelayedStopAudioEngine extends _FakeAudioEngine {
  Completer<void>? _pendingStopCompleter;

  @override
  Future<void> stop() {
    stopCallCount += 1;
    final completer = Completer<void>();
    _pendingStopCompleter = completer;
    return completer.future;
  }

  void completePendingStop() {
    _pendingStopCompleter?.complete();
    _pendingStopCompleter = null;
  }
}

class _FakeLinkedAudioClipLoader implements LinkedAudioClipLoader {
  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    final samples = Float32List.fromList(
      List<double>.generate(
        5000,
        (index) => math.sin((index / 5000) * math.pi * 48).abs(),
      ),
    );

    return ExportAudioClip(
      samples: samples,
      sampleRate: 1000,
      channelCount: 1,
    );
  }
}

class _EditableSongRepository implements SongRepository {
  _EditableSongRepository({required Song? song}) : _song = song;

  final Song? _song;
  final List<Song> savedSongs = [];

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Stream<Song?> watchSongById(String songId) async* {
    yield _song;
  }

  @override
  Future<void> saveSong(Song song) async {
    savedSongs.add(song);
  }

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Future<void> deleteSong(String songId) => throw UnimplementedError();

  @override
  Future<List<Song>> getAllSongs() => throw UnimplementedError();

  @override
  Future<Song?> getSongById(String songId) => throw UnimplementedError();

  @override
  Future<Song> loadSong(String songId) => throw UnimplementedError();

  @override
  Stream<List<Song>> watchAllSongs() => throw UnimplementedError();
}
