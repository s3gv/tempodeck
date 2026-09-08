import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:logging/logging.dart';

import '../../core/audio/export_engine.dart' show ExportAudioClip;
import '../../core/audio/i_audio_engine.dart';
import '../../core/audio/i_export_engine.dart';
import '../../core/audio/tempo_map_evaluator.dart';
import '../../core/audio/text_to_speech_client.dart';
import '../../core/domain/accent_level.dart';
import '../../core/domain/audio_cue.dart';
import '../../core/domain/linked_audio_file.dart';
import '../../core/domain/song.dart';
import '../../core/domain/subdivision.dart';
import '../../core/files/linked_audio_file_storage.dart';
import '../../core/files/linked_audio_import_service.dart';
import '../../core/files/linked_audio_picker.dart';
import '../../core/providers/app_variant_provider.dart';
import '../../core/providers/audio_mixer_provider.dart';
import '../../core/providers/service_providers.dart';
import '../../core/validation/song_write_validator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_dialog.dart';
import '../../core/widgets/td_animated_background.dart';
import '../../core/widgets/td_button.dart';
import '../../core/widgets/td_card.dart';
import '../../core/widgets/td_dropdown_card.dart';
import '../../core/widgets/td_live_access_bar.dart';
import '../../core/widgets/td_loop_expanded_accent_grid.dart';
import '../../core/widgets/td_slider.dart';
import '../../core/widgets/td_toggle.dart';
import '../../core/providers/repository_providers.dart';
import '../export/export_sheet.dart';
import '../live/live_view_context.dart';
import 'song_details_provider.dart';
import 'song_editor_controller.dart';

class SongEditorScreen extends ConsumerWidget {
  const SongEditorScreen({
    super.key,
    required this.songId,
    this.showScaffold = true,
  });

  final String songId;
  final bool showScaffold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songAsync = ref.watch(songDetailsProvider(songId));
    final isMobile = !ref.watch(appVariantProvider).isDesktop;

    final body = songAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (song) {
          if (song == null) {
            return const Center(child: Text('Song not found'));
          }

          // On desktop the play button in the navigation rail reads the
          // activeEditorSongProvider to know which song to launch.
          Future.microtask(() {
            ref.read(activeEditorSongProvider.notifier).state = song;
          });

          final form = _SongEditorForm(
            song: song,
            addBottomPadding: isMobile,
            onPlay: isMobile
                ? (currentSong) {
                    ref
                        .read(liveViewContextProvider.notifier)
                        .set(SongViewContext(song: currentSong));
                    context.go('/songs/${song.id}/live');
                  }
                : null,
          );

          return form;
        },
      );

    if (!showScaffold) {
      return body;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Song'),
        backgroundColor: Colors.transparent,
        actions: [
          if (songAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export',
              onPressed: () {
                final song = songAsync.valueOrNull!;
                showExportSheet(
                  context: context,
                  source: SongExportSource(song.id),
                  title: song.title,
                );
              },
            ),
        ],
      ),
      body: TDAnimatedBackground(child: body),
    );
  }
}

class _SongEditorForm extends ConsumerStatefulWidget {
  const _SongEditorForm({
    required this.song,
    this.addBottomPadding = false,
    this.onPlay,
  });

  final Song song;
  final bool addBottomPadding;

  /// Called when the user taps Play. Receives the current editor state as a
  /// [Song] so the live view uses the latest values, not stale DB data.
  final void Function(Song currentSong)? onPlay;

  @override
  ConsumerState<_SongEditorForm> createState() => _SongEditorFormState();
}

class _SongEditorFormState extends ConsumerState<_SongEditorForm> {
  static const _tempoMapEvaluator = TempoMapEvaluator();
  static const int _defaultEnabledCountInBars = 2;
  static const _autoSaveDebounce = Duration(milliseconds: 500);
  static final Logger _logger = Logger('SongEditorForm');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _startBpmController;
  late final TextEditingController _countInBarsController;
  late final TextEditingController _endBarController;

  late int _startBpm;
  late int _beatsPerBar;
  late int _beatUnit;
  late bool _isCountInEnabled;
  late List<SongTempoChange> _tempoChanges;
  late List<SongLoop> _loops;
  late List<SongEvent> _songEvents;
  late List<SongBarBeatPattern> _beatPatterns;
  LinkedAudioFile? _linkedAudio;
  bool _isRegenerating = false;
  late final SongEditorController _cachedController;
  Timer? _autoSaveTimer;
  Future<void>? _pendingAutoSave;
  final List<String> _pendingFileDeletions = [];
  String? _initializedSongId;

  @override
  void initState() {
    super.initState();
    _cachedController = ref.read(songEditorControllerProvider);
    _titleController = TextEditingController();
    _startBpmController = TextEditingController();
    _countInBarsController = TextEditingController();
    _endBarController = TextEditingController();
    _titleController.addListener(_scheduleAutoSave);
    _countInBarsController.addListener(_scheduleAutoSave);
    _endBarController.addListener(_scheduleAutoSave);
    _syncFromSong(widget.song);
  }

  @override
  void didUpdateWidget(covariant _SongEditorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_initializedSongId != widget.song.id) {
      _syncFromSong(widget.song);
    }
  }

  @override
  void dispose() {
    if (_autoSaveTimer != null) {
      _autoSaveTimer!.cancel();
      _autoSaveTimer = null;
      _flushValidStateOnDispose();
    }
    _titleController.removeListener(_scheduleAutoSave);
    _countInBarsController.removeListener(_scheduleAutoSave);
    _endBarController.removeListener(_scheduleAutoSave);
    _titleController.dispose();
    _startBpmController.dispose();
    _countInBarsController.dispose();
    _endBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = Form(
      key: _formKey,
      child: ListView(
        key: const Key('songEditorScrollView'),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, widget.addBottomPadding ? 100 : AppSpacing.md,
        ),
        children: [
          TextFormField(
            key: const Key('songEditorTitleField'),
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                return null;
              }

              return 'Title must not be empty';
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _SongTempoField(
            sliderKey: const Key('songEditorBpmSlider'),
            textFieldKey: const Key('songEditorBpmField'),
            label: 'Start BPM',
            bpm: _startBpm,
            controller: _startBpmController,
            onChanged: _handleStartBpmChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          _SongMeterSelectorRow(
            beatsPerBarKey: const Key('songEditorBeatsPerBarField'),
            beatUnitKey: const Key('songEditorBeatUnitField'),
            beatsPerBar: _beatsPerBar,
            beatUnit: _beatUnit,
            onBeatsPerBarChanged: (value) {
                    setState(() {
                      _beatsPerBar = value;
                    });
                    _scheduleAutoSave();
                  },
            onBeatUnitChanged: (value) {
                    setState(() {
                      _beatUnit = value;
                    });
                    _scheduleAutoSave();
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          _CountInSection(
            isEnabled: _isCountInEnabled,
            controller: _countInBarsController,
            onEnabledChanged: _handleCountInEnabledChanged,
            validateIntField: _validateCountInBarsField,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('songEditorEndBarField'),
            controller: _endBarController,
            decoration: const InputDecoration(labelText: 'End bar'),
            keyboardType: TextInputType.number,
            validator: (value) => _validateIntField(
              value: value,
              label: 'End bar',
              minimum: SongWriteValidator.minimumEndBar,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _TempoMapVisualization(
            song: _draftSong,
            evaluator: _tempoMapEvaluator,
            tempoChanges: _sortedTempoChanges,
            onAdd: _promptAddTempoChange,
            onEdit: _promptEditTempoChange,
            onDelete: _deleteTempoChange,
          ),
          const SizedBox(height: AppSpacing.lg),
          _LoopsSection(
            loops: _sortedLoops,
            onAdd: _promptAddLoop,
            onEdit: _promptEditLoop,
            onDelete: _deleteLoop,
          ),
          const SizedBox(height: AppSpacing.lg),
          _SongEventsSection(
            songEvents: _sortedSongEvents,
            onAdd: _promptAddSongEvent,
            onEdit: _promptEditSongEvent,
            onDelete: _deleteSongEvent,
          ),
          const SizedBox(height: AppSpacing.lg),
          _BeatPatternsSection(
            beatPatterns: _sortedBeatPatterns,
            onAdd: _promptAddBeatPattern,
            onEdit: _promptEditBeatPattern,
            onDelete: _deleteBeatPattern,
          ),
          if (_beatPatterns.isNotEmpty)
            TDLoopExpandedAccentGrid(song: _draftSong),
          const SizedBox(height: AppSpacing.lg),
          _LinkedAudioSection(
            linkedAudio: _linkedAudio,
            onAttach: _attachLinkedAudio,
            onReplace: _replaceLinkedAudio,
            onRemove: _removeLinkedAudio,
            onChanged: (linkedAudio) {
              setState(() {
                _linkedAudio = linkedAudio;
              });
              _scheduleAutoSave();
            },
            validateIntField: _validateIntField,
          ),
          const SizedBox(height: AppSpacing.lg),
          TDButton(
            key: const Key('songEditorRegenerateBeatmapButton'),
            label: _isRegenerating
                ? 'Regenerating...'
                : 'Regenerate Beatmap',
            onPressed:
                _isRegenerating ? null : () => _regenerateBeatmap(context),
          ),
        ],
      ),
    );

    if (widget.onPlay == null) {
      return form;
    }

    return Stack(
      children: [
        form,
        TDLiveAccessBar(
          onPlay: () async {
            await _flushAutoSave();
            final freshSong = await ref
                .read(songRepositoryProvider)
                .getSongById(widget.song.id);
            if (freshSong == null || !mounted) return;
            widget.onPlay?.call(freshSong);
          },
        ),
      ],
    );
  }

  void _syncFromSong(Song song) {
    _initializedSongId = song.id;
    _titleController.text = song.title;
    _startBpm = song.startBpm;
    _startBpmController.text = song.startBpm.toString();
    _beatsPerBar = song.beatsPerBar;
    _isCountInEnabled = song.countInBars > 0;
    _countInBarsController.text = _isCountInEnabled
        ? song.countInBars.toString()
        : _defaultEnabledCountInBars.toString();
    _endBarController.text = song.endBar.toString();
    _beatUnit = song.beatUnit;
    _tempoChanges = List.of(song.tempoChanges);
    _loops = List.of(song.loops);
    _songEvents = List.of(song.songEvents);
    _beatPatterns = List.of(song.beatPatterns);
    _linkedAudio = _normalizedLinkedAudio(song.linkedAudio);
  }

  String? _validateIntField({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null) {
      return '$label must be a number';
    }

    if (parsed < minimum) {
      return '$label must be at least $minimum';
    }

    if (maximum != null && parsed > maximum) {
      return '$label must be at most $maximum';
    }

    return null;
  }

  String? _validateCountInBarsField({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) {
    if (!_isCountInEnabled) {
      return null;
    }

    final effectiveMinimum = minimum <= 0 ? 1 : minimum;
    return _validateIntField(
      value: value,
      label: label,
      minimum: effectiveMinimum,
      maximum: maximum,
    );
  }

  void _handleStartBpmChanged(int value) {
    if (_startBpm == value && _startBpmController.text == '$value') {
      return;
    }

    setState(() {
      _startBpm = value;
      _startBpmController.text = '$value';
    });
    _scheduleAutoSave();
  }

  void _handleCountInEnabledChanged(bool isEnabled) {
    setState(() {
      _isCountInEnabled = isEnabled;
      if (isEnabled) {
        final currentValue = int.tryParse(_countInBarsController.text);
        if (currentValue == null || currentValue <= 0) {
          _countInBarsController.text = _defaultEnabledCountInBars.toString();
        }
      }
    });
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDebounce, _autoSave);
  }

  void _autoSave() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    _persistCurrentState();
  }

  void _persistCurrentState() {
    final controller = ref.read(songEditorControllerProvider);
    final songId = widget.song.id;
    final future = controller
        .saveSongDetails(
          song: widget.song,
          title: _titleController.text,
          startBpm: _startBpm,
          beatsPerBar: _beatsPerBar,
          beatUnit: _beatUnit,
          countInBars: _isCountInEnabled
              ? (int.tryParse(_countInBarsController.text) ??
                  _defaultEnabledCountInBars)
              : 0,
          endBar: int.tryParse(_endBarController.text) ?? widget.song.endBar,
          tempoChanges: _tempoChanges,
          loops: _loops,
          songEvents: _songEvents,
          beatPatterns: _beatPatterns,
          linkedAudio: _normalizedLinkedAudio(_linkedAudio),
        )
        .then((_) => controller.regenerateBeatmap(songId));

    _pendingAutoSave = future.then(
      (_) => _flushPendingFileDeletions(),
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning('Auto-save failed.', error, stackTrace);
      },
    );
  }

  /// Flushes a pending auto-save during [dispose], where [FormState] is no
  /// longer available. Replicates the form validation contract inline: every
  /// text field must parse to a valid value. If any field is invalid the save
  /// is skipped entirely — the last successful auto-save already persisted a
  /// consistent snapshot, and we must not coerce or default invalid input.
  void _flushValidStateOnDispose() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final endBar = int.tryParse(_endBarController.text);
    if (endBar == null) {
      return;
    }
    final int countInBars;
    if (_isCountInEnabled) {
      final parsed = int.tryParse(_countInBarsController.text);
      if (parsed == null || parsed <= 0) {
        return;
      }
      countInBars = parsed;
    } else {
      countInBars = 0;
    }

    final songId = widget.song.id;
    _cachedController
        .saveSongDetails(
          song: widget.song,
          title: title,
          startBpm: _startBpm,
          beatsPerBar: _beatsPerBar,
          beatUnit: _beatUnit,
          countInBars: countInBars,
          endBar: endBar,
          tempoChanges: _tempoChanges,
          loops: _loops,
          songEvents: _songEvents,
          beatPatterns: _beatPatterns,
          linkedAudio: _normalizedLinkedAudio(_linkedAudio),
        )
        .then((_) => _cachedController.regenerateBeatmap(songId))
        .then(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _logger.warning('Dispose auto-save failed.', error, stackTrace);
          },
        );
  }

  Future<void> _flushAutoSave() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _autoSave();
    await _pendingAutoSave;
  }

  Future<void> _regenerateBeatmap(BuildContext context) async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot regenerate beatmap: fix form errors first'),
        ),
      );
      return;
    }

    setState(() {
      _isRegenerating = true;
    });

    try {
      await _flushAutoSave();
      await ref
          .read(songEditorControllerProvider)
          .regenerateBeatmap(widget.song.id);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beatmap regenerated')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not regenerate beatmap: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRegenerating = false;
        });
      }
    }
  }

  Song get _draftSong {
    return widget.song.copyWith(
      title: _titleController.text.trim().isEmpty
          ? widget.song.title
          : _titleController.text.trim(),
      startBpm: _startBpm,
      beatsPerBar: _beatsPerBar,
      beatUnit: _beatUnit,
      countInBars: _isCountInEnabled
          ? (int.tryParse(_countInBarsController.text) ??
              _defaultEnabledCountInBars)
          : 0,
      endBar: int.tryParse(_endBarController.text) ?? widget.song.endBar,
      tempoChanges: _tempoChanges,
      loops: _loops,
      songEvents: _songEvents,
      beatPatterns: _beatPatterns,
      linkedAudio: _normalizedLinkedAudio(_linkedAudio),
      clearLinkedAudio: _linkedAudio == null,
    );
  }

  List<SongTempoChange> get _sortedTempoChanges {
    final changes = List.of(_tempoChanges)
      ..sort((left, right) => left.barIndex.compareTo(right.barIndex));
    return changes;
  }

  List<SongLoop> get _sortedLoops {
    final loops = List.of(_loops)
      ..sort((left, right) => left.startBar.compareTo(right.startBar));
    return loops;
  }

  List<SongEvent> get _sortedSongEvents {
    final events = List.of(_songEvents)
      ..sort((left, right) => left.barIndex.compareTo(right.barIndex));
    return events;
  }

  List<SongBarBeatPattern> get _sortedBeatPatterns {
    final patterns = List.of(_beatPatterns)
      ..sort((left, right) => left.barIndex.compareTo(right.barIndex));
    return patterns;
  }

  Future<void> _promptAddTempoChange() async {
    final tempoChange = await _showTempoChangeDialog(context);
    if (tempoChange == null || !mounted) {
      return;
    }

    setState(() {
      _tempoChanges = [..._tempoChanges, tempoChange];
    });
    _scheduleAutoSave();
  }

  Future<void> _promptEditTempoChange(SongTempoChange tempoChange) async {
    final updatedTempoChange = await _showTempoChangeDialog(
      context,
      initialValue: tempoChange,
    );
    if (updatedTempoChange == null || !mounted) {
      return;
    }

    setState(() {
      _tempoChanges = [
        for (final currentTempoChange in _tempoChanges)
          if (currentTempoChange.id == tempoChange.id)
            updatedTempoChange
          else
            currentTempoChange,
      ];
    });
    _scheduleAutoSave();
  }

  void _deleteTempoChange(String tempoChangeId) {
    setState(() {
      _tempoChanges = _tempoChanges
          .where((tempoChange) => tempoChange.id != tempoChangeId)
          .toList(growable: false);
    });
    _scheduleAutoSave();
  }

  Future<void> _promptAddLoop() async {
    final loop = await _showLoopDialog(context);
    if (loop == null || !mounted) {
      return;
    }

    setState(() {
      _loops = [..._loops, loop];
    });
    _scheduleAutoSave();
  }

  Future<void> _promptEditLoop(SongLoop loop) async {
    final updatedLoop = await _showLoopDialog(
      context,
      initialValue: loop,
    );
    if (updatedLoop == null || !mounted) {
      return;
    }

    setState(() {
      _loops = [
        for (final currentLoop in _loops)
          if (currentLoop.id == loop.id) updatedLoop else currentLoop,
      ];
    });
    _scheduleAutoSave();
  }

  void _deleteLoop(String loopId) {
    setState(() {
      _loops = _loops.where((loop) => loop.id != loopId).toList(growable: false);
    });
    _scheduleAutoSave();
  }

  Future<void> _promptAddSongEvent() async {
    final songEvent = await _showSongEventDialog(context);
    if (songEvent == null || !mounted) {
      return;
    }

    setState(() {
      _songEvents = [..._songEvents, songEvent];
    });
    _scheduleAutoSave();
  }

  Future<void> _promptEditSongEvent(SongEvent songEvent) async {
    final updatedSongEvent = await _showSongEventDialog(
      context,
      initialValue: songEvent,
    );
    if (updatedSongEvent == null || !mounted) {
      return;
    }

    _deferReplacedCustomFileDeletion(
      oldEvent: songEvent,
      newEvent: updatedSongEvent,
    );

    setState(() {
      _songEvents = [
        for (final currentSongEvent in _songEvents)
          if (currentSongEvent.id == songEvent.id) updatedSongEvent else currentSongEvent,
      ];
    });
    _scheduleAutoSave();
  }

  void _deleteSongEvent(String songEventId) {
    setState(() {
      _songEvents = _songEvents
          .where((songEvent) => songEvent.id != songEventId)
          .toList(growable: false);
    });
    _scheduleAutoSave();
  }

  Future<void> _promptAddBeatPattern() async {
    final beatPattern = await _showBeatPatternDialog(context);
    if (beatPattern == null || !mounted) {
      return;
    }

    setState(() {
      _beatPatterns = [..._beatPatterns, beatPattern];
    });
    _scheduleAutoSave();
  }

  Future<void> _promptEditBeatPattern(SongBarBeatPattern beatPattern) async {
    final updatedBeatPattern = await _showBeatPatternDialog(
      context,
      initialValue: beatPattern,
    );
    if (updatedBeatPattern == null || !mounted) {
      return;
    }

    setState(() {
      _beatPatterns = [
        for (final currentBeatPattern in _beatPatterns)
          if (currentBeatPattern.id == beatPattern.id)
            updatedBeatPattern
          else
            currentBeatPattern,
      ];
    });
    _scheduleAutoSave();
  }

  void _deleteBeatPattern(String beatPatternId) {
    setState(() {
      _beatPatterns = _beatPatterns
          .where((beatPattern) => beatPattern.id != beatPatternId)
          .toList(growable: false);
    });
    _scheduleAutoSave();
  }

  Future<SongTempoChange?> _showTempoChangeDialog(
    BuildContext context, {
    SongTempoChange? initialValue,
  }) async {
    return showDialog<SongTempoChange>(
      context: context,
      builder: (dialogContext) => _TempoChangeDialog(
        initialValue: initialValue,
        initialBpm: initialValue?.bpm ?? _startBpm,
        initialBeatsPerBar: initialValue?.beatsPerBar ?? _beatsPerBar,
        defaultBeatUnit: _beatUnit,
        maximumEndBar:
            int.tryParse(_endBarController.text) ?? _draftSong.endBar,
        createTempoChange: ref.read(songEditorControllerProvider).createTempoChange,
        validateIntField: _validateIntField,
      ),
    );
  }

  Future<SongLoop?> _showLoopDialog(
    BuildContext context, {
    SongLoop? initialValue,
  }) async {
    final songEditorController = ref.read(songEditorControllerProvider);
    return showDialog<SongLoop>(
      context: context,
      builder: (dialogContext) => _SongLoopDialog(
        song: _draftSong,
        initialValue: initialValue,
        maximumEndBar: int.tryParse(_endBarController.text) ?? _draftSong.endBar,
        createLoop: songEditorController.createLoop,
        createTempoChange: songEditorController.createTempoChange,
        createSongEvent: songEditorController.createSongEvent,
        createBeatPattern: songEditorController.createBeatPattern,
        validateIntField: _validateIntField,
        linkedAudioPicker: ref.read(linkedAudioPickerProvider),
        linkedAudioImportService: ref.read(linkedAudioImportServiceProvider),
        linkedAudioFileStorage: ref.read(linkedAudioFileStorageProvider),
        audioEngine: ref.read(audioEngineProvider),
        cueVolumeFactor:
            ref.read(audioMixerControllerProvider.notifier).cueVolumeFactor(),
        onReplacedFilePath: _pendingFileDeletions.add,
      ),
    );
  }

  Future<SongEvent?> _showSongEventDialog(
    BuildContext context, {
    SongEvent? initialValue,
  }) async {
    return showDialog<SongEvent>(
      context: context,
      builder: (dialogContext) => _SongEventDialog(
        initialValue: initialValue,
        maximumEndBar: int.tryParse(_endBarController.text) ?? _draftSong.endBar,
        createSongEvent: ref.read(songEditorControllerProvider).createSongEvent,
        validateIntField: _validateIntField,
        linkedAudioPicker: ref.read(linkedAudioPickerProvider),
        linkedAudioImportService: ref.read(linkedAudioImportServiceProvider),
        linkedAudioFileStorage: ref.read(linkedAudioFileStorageProvider),
        audioEngine: ref.read(audioEngineProvider),
        cueVolumeFactor:
            ref.read(audioMixerControllerProvider.notifier).cueVolumeFactor(),
      ),
    );
  }

  Future<SongBarBeatPattern?> _showBeatPatternDialog(
    BuildContext context, {
    SongBarBeatPattern? initialValue,
  }) async {
    return showDialog<SongBarBeatPattern>(
      context: context,
      builder: (dialogContext) => _BeatPatternDialog(
        initialValue: initialValue,
        defaultBeatsPerBar: _beatsPerBar,
        maximumEndBar: int.tryParse(_endBarController.text) ?? _draftSong.endBar,
        createBeatPattern: ref.read(songEditorControllerProvider).createBeatPattern,
        validateIntField: _validateIntField,
        beatsPerBarResolver: _beatsPerBarAtSongBar,
      ),
    );
  }

  int _beatsPerBarAtSongBar(int barIndex) {
    final clampedBarIndex = barIndex.clamp(
      SongWriteValidator.minimumBarIndex,
      _draftSong.endBar,
    );
    try {
      return _tempoMapEvaluator.resolveAtBar(_draftSong, clampedBarIndex).beatsPerBar;
    } on ArgumentError {
      return _beatsPerBar;
    }
  }

  Future<void> _attachLinkedAudio() async {
    final pickedFile = await ref.read(linkedAudioPickerProvider).pickAudioFile();
    if (pickedFile == null || !mounted) {
      return;
    }

    final importedFile = await ref
        .read(linkedAudioImportServiceProvider)
        .importPickedAudioFile(pickedFile);
    if (!mounted) {
      return;
    }

    setState(() {
      _linkedAudio = LinkedAudioFile(
        filePath: importedFile.filePath,
        displayName: importedFile.displayName,
        volumePercent: 100,
      );
    });
    _scheduleAutoSave();
  }

  Future<void> _replaceLinkedAudio() async {
    final currentLinkedAudio = _linkedAudio;
    final pickedFile = await ref.read(linkedAudioPickerProvider).pickAudioFile();
    if (pickedFile == null || !mounted) {
      return;
    }

    final importedFile = await ref
        .read(linkedAudioImportServiceProvider)
        .importPickedAudioFile(pickedFile);
    if (!mounted) {
      return;
    }

    if (currentLinkedAudio != null) {
      _pendingFileDeletions.add(currentLinkedAudio.filePath);
    }

    setState(() {
      _linkedAudio = LinkedAudioFile(
        filePath: importedFile.filePath,
        displayName: importedFile.displayName,
        offsetMilliseconds: currentLinkedAudio?.offsetMilliseconds ?? 0,
        volumePercent: currentLinkedAudio?.volumePercent ?? 100,
        playInLiveMode: currentLinkedAudio?.playInLiveMode ?? true,
      );
    });
    _scheduleAutoSave();
  }

  void _removeLinkedAudio() {
    final oldPath = _linkedAudio?.filePath;
    setState(() {
      _linkedAudio = null;
    });
    if (oldPath != null) {
      _pendingFileDeletions.add(oldPath);
    }
    _scheduleAutoSave();
  }

  void _flushPendingFileDeletions() {
    final paths = List<String>.of(_pendingFileDeletions);
    _pendingFileDeletions.clear();
    for (final path in paths) {
      _deleteLinkedAudioFile(path);
    }
  }

  /// Schedules deletion of the old custom cue file when a song event's custom
  /// file path changes. The actual deletion happens after a successful save.
  void _deferReplacedCustomFileDeletion({
    required SongEvent oldEvent,
    required SongEvent newEvent,
  }) {
    final oldPath = oldEvent.audioCue?.customFilePath;
    final newPath = newEvent.audioCue?.customFilePath;
    if (oldPath != null && oldPath.isNotEmpty && oldPath != newPath) {
      _pendingFileDeletions.add(oldPath);
    }
  }

  void _deleteLinkedAudioFile(String filePath) {
    ref
        .read(linkedAudioFileStorageProvider)
        .deleteFromStorage(filePath)
        .catchError((Object error) {
      _logger.warning('Failed to delete linked audio file.', error);
    });
  }

  LinkedAudioFile? _normalizedLinkedAudio(LinkedAudioFile? linkedAudio) {
    if (linkedAudio == null) {
      return null;
    }

    return LinkedAudioFile(
      filePath: linkedAudio.filePath,
      displayName: linkedAudio.displayName,

      offsetMilliseconds: linkedAudio.offsetMilliseconds,
      volumePercent: linkedAudio.volumePercent,
      playInLiveMode: linkedAudio.playInLiveMode,
    );
  }
}

class _SongTempoField extends StatelessWidget {
  const _SongTempoField({
    required this.sliderKey,
    required this.textFieldKey,
    required this.label,
    required this.bpm,
    required this.controller,
    required this.onChanged,
  });

  final Key sliderKey;
  final Key textFieldKey;
  final String label;
  final int bpm;
  final TextEditingController controller;
  final ValueChanged<int>? onChanged;

  static const _stepperIconSize = 24.0;

  void _stepBpm(int delta) {
    final next = (bpm + delta).clamp(
      SongWriteValidator.minimumBpm,
      SongWriteValidator.maximumBpm,
    );
    if (next == bpm) return;
    controller.text = '$next';
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final isAtMin = bpm <= SongWriteValidator.minimumBpm;
    final isAtMax = bpm >= SongWriteValidator.maximumBpm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextTheme.heading3),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('bpm-decrement'),
              onPressed:
                  onChanged == null || isAtMin ? null : () => _stepBpm(-1),
              icon: Icon(
                Icons.remove_circle_outline,
                size: _stepperIconSize,
                color: onChanged == null || isAtMin
                    ? AppColors.textMuted
                    : AppColors.primary,
              ),
            ),
            SizedBox(
              width: AppSpacing.xxl,
              child: Text(
                '$bpm',
                style: AppTextTheme.numericLarge,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              key: const Key('bpm-increment'),
              onPressed:
                  onChanged == null || isAtMax ? null : () => _stepBpm(1),
              icon: Icon(
                Icons.add_circle_outline,
                size: _stepperIconSize,
                color: onChanged == null || isAtMax
                    ? AppColors.textMuted
                    : AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TDSlider(
          key: sliderKey,
          value: bpm.toDouble(),
          min: SongWriteValidator.minimumBpm.toDouble(),
          max: SongWriteValidator.maximumBpm.toDouble(),
          divisions:
              SongWriteValidator.maximumBpm - SongWriteValidator.minimumBpm,
          onChanged: onChanged == null ? null : (value) => onChanged!(value.round()),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: textFieldKey,
          controller: controller,
          enabled: onChanged != null,
          decoration: const InputDecoration(labelText: 'BPM'),
          keyboardType: TextInputType.number,
          validator: (value) => _validateBpm(value),
          onChanged: onChanged == null
              ? null
              : (value) {
                  final parsed = int.tryParse(value);
                  if (parsed == null) {
                    return;
                  }
                  if (parsed < SongWriteValidator.minimumBpm ||
                      parsed > SongWriteValidator.maximumBpm) {
                    return;
                  }
                  onChanged!(parsed);
                },
        ),
      ],
    );
  }

  String? _validateBpm(String? value) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null) {
      return 'BPM must be a number';
    }
    if (parsed < SongWriteValidator.minimumBpm) {
      return 'BPM must be at least ${SongWriteValidator.minimumBpm}';
    }
    if (parsed > SongWriteValidator.maximumBpm) {
      return 'BPM must be at most ${SongWriteValidator.maximumBpm}';
    }
    return null;
  }
}

class _CountInSection extends StatelessWidget {
  const _CountInSection({
    required this.isEnabled,
    required this.controller,
    required this.onEnabledChanged,
    required this.validateIntField,
  });

  final bool isEnabled;
  final TextEditingController controller;
  final ValueChanged<bool>? onEnabledChanged;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Count-in',
                style: AppTextTheme.heading3,
              ),
            ),
            TDToggle(
              value: isEnabled,
              onChanged: onEnabledChanged,
            ),
          ],
        ),
        if (isEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('songEditorCountInBarsField'),
            controller: controller,
            decoration: const InputDecoration(labelText: 'Count-in bars'),
            keyboardType: TextInputType.number,
            validator: (value) => validateIntField(
              value: value,
              label: 'Count-in bars',
              minimum: SongWriteValidator.minimumCountInBars,
            ),
          ),
        ],
      ],
    );
  }
}

class _SongMeterSelectorRow extends StatelessWidget {
  const _SongMeterSelectorRow({
    required this.beatsPerBarKey,
    required this.beatUnitKey,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.onBeatsPerBarChanged,
    required this.onBeatUnitChanged,
  });

  final Key beatsPerBarKey;
  final Key beatUnitKey;
  final int beatsPerBar;
  final int beatUnit;
  final ValueChanged<int>? onBeatsPerBarChanged;
  final ValueChanged<int>? onBeatUnitChanged;

  @override
  Widget build(BuildContext context) {
    final isEnabled =
        onBeatsPerBarChanged != null && onBeatUnitChanged != null;

    return IgnorePointer(
      ignoring: !isEnabled,
      child: Row(
        children: [
          Expanded(
            child: TDDropdownCard<int>(
              key: beatsPerBarKey,
              label: 'Beats Per Bar',
              value: beatsPerBar,
              options: [
                for (var beats = SongWriteValidator.minimumBeatsPerBar;
                    beats <= SongWriteValidator.maximumBeatsPerBar;
                    beats += 1)
                  beats,
              ],
              itemLabel: (value) => '$value',
              onChanged: onBeatsPerBarChanged ?? (_) {},
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TDDropdownCard<int>(
              key: beatUnitKey,
              label: 'Beat Unit',
              value: beatUnit,
              options: SongWriteValidator.supportedBeatUnits.toList(),
              itemLabel: (value) => '$value',
              onChanged: onBeatUnitChanged ?? (_) {},
            ),
          ),
        ],
      ),
    );
  }
}

class _TempoMapVisualization extends StatelessWidget {
  const _TempoMapVisualization({
    required this.song,
    required this.evaluator,
    required this.tempoChanges,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final Song song;
  final TempoMapEvaluator evaluator;
  final List<SongTempoChange> tempoChanges;
  final VoidCallback onAdd;
  final void Function(SongTempoChange) onEdit;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    List<TempoMapSegment> segments;
    try {
      segments = evaluator.buildSegments(song);
    } on ArgumentError catch (error) {
      return Text('Tempo map unavailable: $error');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Tempo map',
                style: AppTextTheme.heading3,
              ),
            ),
            TDButton(
              key: const Key('songEditorAddTempoChangeButton'),
              label: 'Add',
              icon: Icons.add,
              variant: TDButtonVariant.secondary,
              onPressed: onAdd,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (context) {
              final segment = segments[i];
              final linkedTempoChange = _tempoChangeForSegment(segment);
              return ListTile(
                key: Key('tempoMapSegmentTile-${segment.startBarIndex}'),
                title: Text(
                  'Bars ${segment.startBarIndex}-${segment.endBarIndex}',
                ),
                subtitle: Text(
                  '${segment.state.bpm} BPM · '
                  '${segment.state.beatsPerBar}/${segment.state.beatUnit}',
                ),
                trailing: linkedTempoChange == null
                    ? null
                    : PopupMenuButton<_TempoChangeAction>(
                        onSelected: (action) {
                          switch (action) {
                            case _TempoChangeAction.edit:
                              onEdit(linkedTempoChange);
                            case _TempoChangeAction.delete:
                              onDelete(linkedTempoChange.id);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _TempoChangeAction.edit,
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: _TempoChangeAction.delete,
                            child: Text('Delete'),
                          ),
                        ],
                      ),
              );
            },
          ),
        ],
      ],
    );
  }

  SongTempoChange? _tempoChangeForSegment(TempoMapSegment segment) {
    for (final tempoChange in tempoChanges) {
      if (tempoChange.barIndex == segment.startBarIndex) {
        return tempoChange;
      }
    }

    return null;
  }
}

enum _TempoChangeAction { edit, delete }

class _LoopsSection extends StatelessWidget {
  const _LoopsSection({
    required this.loops,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<SongLoop> loops;
  final VoidCallback onAdd;
  final void Function(SongLoop) onEdit;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Loops',
                style: AppTextTheme.heading3,
              ),
            ),
            TDButton(
              key: const Key('songEditorAddLoopButton'),
              label: 'Add',
              icon: Icons.add,
              variant: TDButtonVariant.secondary,
              onPressed: onAdd,
            ),
          ],
        ),
        if (loops.isEmpty)
          const Text('No loops yet')
        else
          ...loops.map(
            (loop) => ListTile(
              key: Key('songLoopTile-${loop.id}'),

              title: Text('Bars ${loop.startBar}-${loop.endBar}'),
              subtitle: Text(
                [
                  '${loop.repeatCount} repeats',
                  if (loop.alternativeEndings.isNotEmpty)
                    '${loop.alternativeEndings.length} alternative endings',
                ].join(' · '),
              ),
              trailing: PopupMenuButton<_SongLoopAction>(
                onSelected: (action) {
                  switch (action) {
                    case _SongLoopAction.edit:
                      onEdit(loop);
                    case _SongLoopAction.delete:
                      onDelete(loop.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SongLoopAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: _SongLoopAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _SongLoopAction { edit, delete }

class _SongEventsSection extends StatelessWidget {
  const _SongEventsSection({
    required this.songEvents,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<SongEvent> songEvents;
  final VoidCallback onAdd;
  final void Function(SongEvent) onEdit;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Song events',
                style: AppTextTheme.heading3,
              ),
            ),
            TDButton(
              key: const Key('songEditorAddSongEventButton'),
              label: 'Add',
              icon: Icons.add,
              variant: TDButtonVariant.secondary,
              onPressed: onAdd,
            ),
          ],
        ),
        if (songEvents.isEmpty)
          const Text('No song events yet')
        else
          ...songEvents.map(
            (songEvent) => ListTile(
              key: Key('songEventTile-${songEvent.id}'),

              title: Text('${songEvent.label} · Bar ${songEvent.barIndex}'),
              subtitle: Text(_songEventSubtitle(songEvent)),
              trailing: PopupMenuButton<_SongEventAction>(
                onSelected: (action) {
                  switch (action) {
                    case _SongEventAction.edit:
                      onEdit(songEvent);
                    case _SongEventAction.delete:
                      onDelete(songEvent.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SongEventAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: _SongEventAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

}

enum _SongEventAction { edit, delete }

class _BeatPatternsSection extends StatelessWidget {
  const _BeatPatternsSection({
    required this.beatPatterns,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<SongBarBeatPattern> beatPatterns;
  final VoidCallback onAdd;
  final void Function(SongBarBeatPattern) onEdit;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Beat patterns',
                style: AppTextTheme.heading3,
              ),
            ),
            TDButton(
              key: const Key('songEditorAddBeatPatternButton'),
              label: 'Add',
              icon: Icons.add,
              variant: TDButtonVariant.secondary,
              onPressed: onAdd,
            ),
          ],
        ),
        if (beatPatterns.isEmpty)
          const Text('No beat patterns yet')
        else
          ...beatPatterns.map(
            (beatPattern) => ListTile(
              key: Key('songBeatPatternTile-${beatPattern.id}'),

              title: Text('Bar ${beatPattern.barIndex}'),
              subtitle: Text(_beatPatternSubtitle(beatPattern)),
              trailing: PopupMenuButton<_BeatPatternAction>(
                onSelected: (action) {
                  switch (action) {
                    case _BeatPatternAction.edit:
                      onEdit(beatPattern);
                    case _BeatPatternAction.delete:
                      onDelete(beatPattern.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _BeatPatternAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: _BeatPatternAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

}

enum _BeatPatternAction { edit, delete }

String _songEventSubtitle(SongEvent songEvent) {
  final audioCue = songEvent.audioCue;
  if (audioCue == null) {
    return 'No audio cue';
  }

  return '${_audioCueLabel(audioCue)} · '
      '${songEvent.audioCueBarsBefore} bars before';
}

String _audioCueLabel(AudioCue audioCue) {
  switch (audioCue.type) {
    case AudioCueType.voice:
      return 'Voice';
    case AudioCueType.customFile:
      return 'Custom file';
    case AudioCueType.intervalSignal:
      return 'Interval signal';
    case AudioCueType.maxSignal:
      return 'Max signal';
    case AudioCueType.lowPulse:
      return 'Low pulse';
    case AudioCueType.midPulse:
      return 'Mid pulse';
    case AudioCueType.highPulse:
      return 'High pulse';
  }
}

String _beatPatternSubtitle(SongBarBeatPattern beatPattern) {
  final accents = beatPattern.accents.map(_accentShortLabelFor).join(' ');
  final repeatPass = beatPattern.repeatPass == null
      ? ''
      : ' · Pass ${beatPattern.repeatPass}';
  return '${beatPattern.subdivision.displayLabel} subdivision · '
      '$accents$repeatPass';
}

class _LinkedAudioSection extends StatelessWidget {
  const _LinkedAudioSection({
    required this.linkedAudio,
    required this.onAttach,
    required this.onReplace,
    required this.onRemove,
    required this.onChanged,
    required this.validateIntField,
  });

  final LinkedAudioFile? linkedAudio;
  final Future<void> Function() onAttach;
  final Future<void> Function() onReplace;
  final VoidCallback onRemove;
  final ValueChanged<LinkedAudioFile> onChanged;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;

  @override
  Widget build(BuildContext context) {
    final linkedAudio = this.linkedAudio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Linked audio',
          style: AppTextTheme.heading3,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (linkedAudio == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TDButton(
              key: const Key('songEditorAttachLinkedAudioButton'),
              label: 'Attach audio file',
              icon: Icons.attach_file,
              variant: TDButtonVariant.secondary,
              onPressed: onAttach,
            ),
          )
        else
          TDCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linkedAudio.displayName,
                    key: const Key('songLinkedAudioDisplayNameText'),
                    style: AppTextTheme.heading3,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(_linkedAudioSummary(linkedAudio)),
                  const SizedBox(height: AppSpacing.md),
                  _InlineLinkedAudioEditor(
                    linkedAudio: linkedAudio,
                    onChanged: onChanged,
                    validateIntField: validateIntField,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 8,
                    children: [
                      TDButton(
                        key: const Key('songEditorReplaceLinkedAudioButton'),
                        label: 'Replace file',
                        variant: TDButtonVariant.secondary,
                        onPressed: onReplace,
                      ),
                      TDButton(
                        key: const Key('songEditorRemoveLinkedAudioButton'),
                        label: 'Remove',
                        variant: TDButtonVariant.secondary,
                        onPressed: onRemove,
                      ),
                    ],
                  ),
                ],
              ),
          ),
      ],
    );
  }

  String _linkedAudioSummary(LinkedAudioFile linkedAudio) {
    final liveModeLabel = linkedAudio.playInLiveMode ? 'Enabled' : 'Disabled';

    return 'Offset ${linkedAudio.offsetMilliseconds}ms · '
        'Live playback $liveModeLabel';
  }
}

class _TempoChangeDialog extends StatefulWidget {
  const _TempoChangeDialog({
    required this.initialValue,
    required this.initialBpm,
    required this.initialBeatsPerBar,
    required this.defaultBeatUnit,
    required this.maximumEndBar,
    required this.createTempoChange,
    required this.validateIntField,
  });

  final SongTempoChange? initialValue;
  final int initialBpm;
  final int initialBeatsPerBar;
  final int defaultBeatUnit;
  final int maximumEndBar;
  final SongTempoChange Function({
    required int barIndex,
    required int bpm,
    required int beatsPerBar,
    required int beatUnit,
  }) createTempoChange;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;

  @override
  State<_TempoChangeDialog> createState() => _TempoChangeDialogState();
}

class _SongLoopDialog extends StatefulWidget {
  const _SongLoopDialog({
    required this.song,
    required this.initialValue,
    required this.maximumEndBar,
    required this.createLoop,
    required this.createTempoChange,
    required this.createSongEvent,
    required this.createBeatPattern,
    required this.validateIntField,
    required this.linkedAudioPicker,
    required this.linkedAudioImportService,
    required this.linkedAudioFileStorage,
    required this.audioEngine,
    required this.cueVolumeFactor,
    required this.onReplacedFilePath,
  });

  final Song song;
  final SongLoop? initialValue;
  final int maximumEndBar;
  final SongLoop Function({
    required int startBar,
    required int endBar,
    required int repeatCount,
    List<SongLoopAlternativeEnding> alternativeEndings,
  }) createLoop;
  final SongTempoChange Function({
    required int barIndex,
    required int bpm,
    required int beatsPerBar,
    required int beatUnit,
  }) createTempoChange;
  final SongEvent Function({
    required int barIndex,
    required String label,
    required AudioCue? audioCue,
    required int audioCueBarsBefore,
  }) createSongEvent;
  final SongBarBeatPattern Function({
    required int barIndex,
    required List<AccentLevel> accents,
    required Subdivision subdivision,
    required int? repeatPass,
  }) createBeatPattern;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;
  final LinkedAudioPicker linkedAudioPicker;
  final LinkedAudioImportService linkedAudioImportService;
  final LinkedAudioFileStorage linkedAudioFileStorage;
  final IAudioEngine audioEngine;
  final double cueVolumeFactor;
  final ValueChanged<String> onReplacedFilePath;

  @override
  State<_SongLoopDialog> createState() => _SongLoopDialogState();
}

class _SongLoopDialogState extends State<_SongLoopDialog> {
  static const _tempoMapEvaluator = TempoMapEvaluator();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _startBarController;
  late final TextEditingController _endBarController;
  late final TextEditingController _repeatCountController;
  late List<_AlternativeEndingDraft> _alternativeEndings;

  @override
  void initState() {
    super.initState();
    _startBarController = TextEditingController(
      text: widget.initialValue?.startBar.toString() ?? '',
    );
    _endBarController = TextEditingController(
      text: widget.initialValue?.endBar.toString() ?? '',
    );
    _repeatCountController = TextEditingController(
      text: widget.initialValue?.repeatCount.toString() ?? '2',
    );
    _alternativeEndings = _buildAlternativeEndingDrafts(
      repeatCount: widget.initialValue?.repeatCount ?? 2,
      initialEndings: widget.initialValue?.alternativeEndings ?? const [],
    );
  }

  @override
  void dispose() {
    _startBarController.dispose();
    _endBarController.dispose();
    _repeatCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: Text(widget.initialValue == null ? 'Add loop' : 'Edit loop'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('songLoopStartBarField'),
                controller: _startBarController,
                decoration: const InputDecoration(labelText: 'Start bar'),
                keyboardType: TextInputType.number,
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Start bar',
                  minimum: SongWriteValidator.minimumBarIndex,
                  maximum: widget.maximumEndBar,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('songLoopEndBarField'),
                controller: _endBarController,
                decoration: const InputDecoration(labelText: 'End bar'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final basicValidation = widget.validateIntField(
                    value: value,
                    label: 'End bar',
                    minimum: SongWriteValidator.minimumBarIndex,
                    maximum: widget.maximumEndBar,
                  );
                  if (basicValidation != null) {
                    return basicValidation;
                  }

                  final startBar = int.tryParse(_startBarController.text);
                  final endBar = int.tryParse(value ?? '');
                  if (startBar != null && endBar != null && endBar < startBar) {
                    return 'End bar must be greater than or equal to start bar';
                  }

                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('songLoopRepeatCountField'),
                controller: _repeatCountController,
                decoration: const InputDecoration(labelText: 'Repeat count'),
                keyboardType: TextInputType.number,
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Repeat count',
                  minimum: SongWriteValidator.minimumRepeatCount,
                ),
                onChanged: _handleRepeatCountChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              _AlternativeEndingsSection(
                endings: _alternativeEndings,
                validateIntField: widget.validateIntField,
                onEnabledChanged: _updateAlternativeEndingEnabled,
                onLengthChanged: _updateAlternativeEndingLength,
                onAddTempoChange: _promptAddAlternativeEndingTempoChange,
                onEditTempoChange: _promptEditAlternativeEndingTempoChange,
                onDeleteTempoChange: _deleteAlternativeEndingTempoChange,
                onAddSongEvent: _promptAddAlternativeEndingSongEvent,
                onEditSongEvent: _promptEditAlternativeEndingSongEvent,
                onDeleteSongEvent: _deleteAlternativeEndingSongEvent,
                onAddBeatPattern: _promptAddAlternativeEndingBeatPattern,
                onEditBeatPattern: _promptEditAlternativeEndingBeatPattern,
                onDeleteBeatPattern: _deleteAlternativeEndingBeatPattern,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.pop(
      context,
      widget.initialValue == null
          ? widget.createLoop(
              startBar: int.parse(_startBarController.text),
              endBar: int.parse(_endBarController.text),
              repeatCount: int.parse(_repeatCountController.text),
              alternativeEndings: _resolvedAlternativeEndings(),
            )
          : SongLoop(
              id: widget.initialValue!.id,
              startBar: int.parse(_startBarController.text),
              endBar: int.parse(_endBarController.text),
              repeatCount: int.parse(_repeatCountController.text),
              alternativeEndings: _resolvedAlternativeEndings(),
            ),
    );
  }

  void _handleRepeatCountChanged(String value) {
    final repeatCount = int.tryParse(value);
    if (repeatCount == null || repeatCount < SongWriteValidator.minimumRepeatCount) {
      return;
    }

    setState(() {
      _alternativeEndings = _buildAlternativeEndingDrafts(
        repeatCount: repeatCount,
        initialEndings: _resolvedAlternativeEndings(),
      );
    });
  }

  void _updateAlternativeEndingEnabled(int repeatPass, bool enabled) {
    setState(() {
      _alternativeEndings = [
        for (final draft in _alternativeEndings)
          if (draft.repeatPass == repeatPass)
            draft.copyWith(enabled: enabled)
          else
            draft,
      ];
    });
  }

  void _updateAlternativeEndingLength(int repeatPass, String lengthBarsText) {
    setState(() {
      _alternativeEndings = [
        for (final draft in _alternativeEndings)
          if (draft.repeatPass == repeatPass)
            draft.copyWith(lengthBarsText: lengthBarsText)
          else
            draft,
      ];
    });
  }

  Future<void> _promptAddAlternativeEndingTempoChange(int repeatPass) async {
    final draft = _draftForPass(repeatPass);
    if (draft == null) {
      return;
    }
    final createdTempoChange = await _showAlternativeEndingTempoChangeDialog(draft);
    if (createdTempoChange == null || !mounted) {
      return;
    }
    setState(() {
      _alternativeEndings = [
        for (final currentDraft in _alternativeEndings)
          if (currentDraft.repeatPass == repeatPass)
            currentDraft.copyWith(
              tempoChanges: [
                ...currentDraft.tempoChanges,
                createdTempoChange,
              ]..sort((left, right) => left.barIndex.compareTo(right.barIndex)),
            )
          else
            currentDraft,
      ];
    });
  }

  Future<void> _promptEditAlternativeEndingTempoChange(
    int repeatPass,
    SongTempoChange tempoChange,
  ) async {
    final draft = _draftForPass(repeatPass);
    if (draft == null) {
      return;
    }
    final updatedTempoChange = await _showAlternativeEndingTempoChangeDialog(
      draft,
      initialValue: tempoChange,
    );
    if (updatedTempoChange == null || !mounted) {
      return;
    }
    setState(() {
      _alternativeEndings = [
        for (final currentDraft in _alternativeEndings)
          if (currentDraft.repeatPass == repeatPass)
            currentDraft.copyWith(
              tempoChanges: [
                for (final currentTempoChange in currentDraft.tempoChanges)
                  if (currentTempoChange.id == tempoChange.id)
                    updatedTempoChange
                  else
                    currentTempoChange,
              ]..sort((left, right) => left.barIndex.compareTo(right.barIndex)),
            )
          else
            currentDraft,
      ];
    });
  }

  void _deleteAlternativeEndingTempoChange(int repeatPass, String tempoChangeId) {
    setState(() {
      _alternativeEndings = [
        for (final draft in _alternativeEndings)
          if (draft.repeatPass == repeatPass)
            draft.copyWith(
              tempoChanges: [
                for (final tempoChange in draft.tempoChanges)
                  if (tempoChange.id != tempoChangeId) tempoChange,
              ],
            )
          else
            draft,
      ];
    });
  }

  Future<void> _promptAddAlternativeEndingSongEvent(int repeatPass) async {
    final draft = _draftForPass(repeatPass);
    if (draft == null) {
      return;
    }
    final createdSongEvent = await _showAlternativeEndingSongEventDialog(draft);
    if (createdSongEvent == null || !mounted) {
      return;
    }
    setState(() {
      _alternativeEndings = [
        for (final currentDraft in _alternativeEndings)
          if (currentDraft.repeatPass == repeatPass)
            currentDraft.copyWith(
              songEvents: [
                ...currentDraft.songEvents,
                createdSongEvent,
              ]..sort((left, right) => left.barIndex.compareTo(right.barIndex)),
            )
          else
            currentDraft,
      ];
    });
  }

  Future<void> _promptEditAlternativeEndingSongEvent(
    int repeatPass,
    SongEvent songEvent,
  ) async {
    final draft = _draftForPass(repeatPass);
    if (draft == null) {
      return;
    }
    final updatedSongEvent = await _showAlternativeEndingSongEventDialog(
      draft,
      initialValue: songEvent,
    );
    if (updatedSongEvent == null || !mounted) {
      return;
    }

    _deferReplacedCustomCueFile(
      oldEvent: songEvent,
      newEvent: updatedSongEvent,
    );

    setState(() {
      _alternativeEndings = [
        for (final currentDraft in _alternativeEndings)
          if (currentDraft.repeatPass == repeatPass)
            currentDraft.copyWith(
              songEvents: [
                for (final currentSongEvent in currentDraft.songEvents)
                  if (currentSongEvent.id == songEvent.id)
                    updatedSongEvent
                  else
                    currentSongEvent,
              ]..sort((left, right) => left.barIndex.compareTo(right.barIndex)),
            )
          else
            currentDraft,
      ];
    });
  }

  void _deleteAlternativeEndingSongEvent(int repeatPass, String songEventId) {
    setState(() {
      _alternativeEndings = [
        for (final draft in _alternativeEndings)
          if (draft.repeatPass == repeatPass)
            draft.copyWith(
              songEvents: [
                for (final songEvent in draft.songEvents)
                  if (songEvent.id != songEventId) songEvent,
              ],
            )
          else
            draft,
      ];
    });
  }

  Future<void> _promptAddAlternativeEndingBeatPattern(int repeatPass) async {
    final draft = _draftForPass(repeatPass);
    if (draft == null) {
      return;
    }
    final createdBeatPattern = await _showAlternativeEndingBeatPatternDialog(draft);
    if (createdBeatPattern == null || !mounted) {
      return;
    }
    setState(() {
      _alternativeEndings = [
        for (final currentDraft in _alternativeEndings)
          if (currentDraft.repeatPass == repeatPass)
            currentDraft.copyWith(
              beatPatterns: [
                ...currentDraft.beatPatterns,
                createdBeatPattern,
              ]..sort((left, right) => left.barIndex.compareTo(right.barIndex)),
            )
          else
            currentDraft,
      ];
    });
  }

  Future<void> _promptEditAlternativeEndingBeatPattern(
    int repeatPass,
    SongBarBeatPattern beatPattern,
  ) async {
    final draft = _draftForPass(repeatPass);
    if (draft == null) {
      return;
    }
    final updatedBeatPattern = await _showAlternativeEndingBeatPatternDialog(
      draft,
      initialValue: beatPattern,
    );
    if (updatedBeatPattern == null || !mounted) {
      return;
    }
    setState(() {
      _alternativeEndings = [
        for (final currentDraft in _alternativeEndings)
          if (currentDraft.repeatPass == repeatPass)
            currentDraft.copyWith(
              beatPatterns: [
                for (final currentBeatPattern in currentDraft.beatPatterns)
                  if (currentBeatPattern.id == beatPattern.id)
                    updatedBeatPattern
                  else
                    currentBeatPattern,
              ]..sort((left, right) => left.barIndex.compareTo(right.barIndex)),
            )
          else
            currentDraft,
      ];
    });
  }

  void _deleteAlternativeEndingBeatPattern(
    int repeatPass,
    String beatPatternId,
  ) {
    setState(() {
      _alternativeEndings = [
        for (final draft in _alternativeEndings)
          if (draft.repeatPass == repeatPass)
            draft.copyWith(
              beatPatterns: [
                for (final beatPattern in draft.beatPatterns)
                  if (beatPattern.id != beatPatternId) beatPattern,
              ],
            )
          else
            draft,
      ];
    });
  }

  List<_AlternativeEndingDraft> _buildAlternativeEndingDrafts({
    required int repeatCount,
    required List<SongLoopAlternativeEnding> initialEndings,
  }) {
    final totalPasses = repeatCount + 1;
    return [
      for (var repeatPass = 1; repeatPass <= totalPasses; repeatPass += 1)
        _AlternativeEndingDraft.fromExisting(
          repeatPass: repeatPass,
          existing: initialEndings
              .where((ending) => ending.repeatPass == repeatPass)
              .firstOrNull,
        ),
    ];
  }

  List<SongLoopAlternativeEnding> _resolvedAlternativeEndings() {
    return [
      for (final draft in _alternativeEndings)
        if (draft.enabled)
          SongLoopAlternativeEnding(
            id: draft.id,
            repeatPass: draft.repeatPass,
            lengthBars: int.parse(draft.lengthBarsText),
            tempoChanges: draft.tempoChanges,
            songEvents: draft.songEvents,
            beatPatterns: draft.beatPatterns,
          ),
    ];
  }

  void _deferReplacedCustomCueFile({
    required SongEvent oldEvent,
    required SongEvent newEvent,
  }) {
    final oldPath = oldEvent.audioCue?.customFilePath;
    final newPath = newEvent.audioCue?.customFilePath;
    if (oldPath != null && oldPath.isNotEmpty && oldPath != newPath) {
      widget.onReplacedFilePath(oldPath);
    }
  }

  _AlternativeEndingDraft? _draftForPass(int repeatPass) {
    for (final draft in _alternativeEndings) {
      if (draft.repeatPass == repeatPass) {
        return draft;
      }
    }
    return null;
  }

  Future<SongTempoChange?> _showAlternativeEndingTempoChangeDialog(
    _AlternativeEndingDraft draft, {
    SongTempoChange? initialValue,
  }) {
    final initialBarIndex = initialValue?.barIndex ?? 1;
    final initialConfig = _alternativeEndingConfigAtBar(draft, initialBarIndex);
    return showDialog<SongTempoChange>(
      context: context,
      builder: (dialogContext) => _TempoChangeDialog(
        initialValue: initialValue,
        initialBpm: initialConfig.bpm,
        initialBeatsPerBar: initialConfig.beatsPerBar,
        defaultBeatUnit: initialConfig.beatUnit,
        maximumEndBar: _maximumAlternativeEndingLength(draft),
        createTempoChange: widget.createTempoChange,
        validateIntField: widget.validateIntField,
      ),
    );
  }

  Future<SongEvent?> _showAlternativeEndingSongEventDialog(
    _AlternativeEndingDraft draft, {
    SongEvent? initialValue,
  }) {
    return showDialog<SongEvent>(
      context: context,
      builder: (dialogContext) => _SongEventDialog(
        initialValue: initialValue,
        maximumEndBar: _maximumAlternativeEndingLength(draft),
        createSongEvent: widget.createSongEvent,
        validateIntField: widget.validateIntField,
        linkedAudioPicker: widget.linkedAudioPicker,
        linkedAudioImportService: widget.linkedAudioImportService,
        linkedAudioFileStorage: widget.linkedAudioFileStorage,
        audioEngine: widget.audioEngine,
        cueVolumeFactor: widget.cueVolumeFactor,
      ),
    );
  }

  Future<SongBarBeatPattern?> _showAlternativeEndingBeatPatternDialog(
    _AlternativeEndingDraft draft, {
    SongBarBeatPattern? initialValue,
  }) {
    return showDialog<SongBarBeatPattern>(
      context: context,
      builder: (dialogContext) => _BeatPatternDialog(
        initialValue: initialValue,
        defaultBeatsPerBar: _alternativeEndingConfigAtBar(
          draft,
          initialValue?.barIndex ?? 1,
        ).beatsPerBar,
        maximumEndBar: _maximumAlternativeEndingLength(draft),
        createBeatPattern: widget.createBeatPattern,
        validateIntField: widget.validateIntField,
        beatsPerBarResolver: (barIndex) =>
            _alternativeEndingConfigAtBar(draft, barIndex).beatsPerBar,
      ),
    );
  }

  _AlternativeEndingConfig _alternativeEndingConfigAtBar(
    _AlternativeEndingDraft draft,
    int barIndex,
  ) {
    final loopStartBar = int.tryParse(_startBarController.text) ?? 1;
    final clampedLoopStartBar = loopStartBar.clamp(1, widget.song.endBar);
    final rootConfig = _tempoMapEvaluator.resolveAtBar(
      widget.song,
      clampedLoopStartBar,
    );
    var bpm = rootConfig.bpm;
    var beatsPerBar = rootConfig.beatsPerBar;
    var beatUnit = rootConfig.beatUnit;

    final targetBarIndex = barIndex.clamp(
      SongWriteValidator.minimumBarIndex,
      _maximumAlternativeEndingLength(draft),
    );
    final sortedTempoChanges = List<SongTempoChange>.of(draft.tempoChanges)
      ..sort((left, right) => left.barIndex.compareTo(right.barIndex));
    for (final tempoChange in sortedTempoChanges) {
      if (tempoChange.barIndex > targetBarIndex) {
        break;
      }
      bpm = tempoChange.bpm;
      beatsPerBar = tempoChange.beatsPerBar;
      beatUnit = tempoChange.beatUnit;
    }

    return _AlternativeEndingConfig(
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
    );
  }

  int _maximumAlternativeEndingLength(_AlternativeEndingDraft draft) {
    return int.tryParse(draft.lengthBarsText) ??
        SongWriteValidator.minimumAlternativeEndingLengthBars;
  }
}

class _AlternativeEndingsSection extends StatelessWidget {
  const _AlternativeEndingsSection({
    required this.endings,
    required this.validateIntField,
    required this.onEnabledChanged,
    required this.onLengthChanged,
    required this.onAddTempoChange,
    required this.onEditTempoChange,
    required this.onDeleteTempoChange,
    required this.onAddSongEvent,
    required this.onEditSongEvent,
    required this.onDeleteSongEvent,
    required this.onAddBeatPattern,
    required this.onEditBeatPattern,
    required this.onDeleteBeatPattern,
  });

  final List<_AlternativeEndingDraft> endings;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;
  final void Function(int repeatPass, bool enabled) onEnabledChanged;
  final void Function(int repeatPass, String lengthBarsText) onLengthChanged;
  final void Function(int repeatPass) onAddTempoChange;
  final void Function(int repeatPass, SongTempoChange tempoChange)
      onEditTempoChange;
  final void Function(int repeatPass, String tempoChangeId)
      onDeleteTempoChange;
  final void Function(int repeatPass) onAddSongEvent;
  final void Function(int repeatPass, SongEvent songEvent) onEditSongEvent;
  final void Function(int repeatPass, String songEventId) onDeleteSongEvent;
  final void Function(int repeatPass) onAddBeatPattern;
  final void Function(int repeatPass, SongBarBeatPattern beatPattern)
      onEditBeatPattern;
  final void Function(int repeatPass, String beatPatternId)
      onDeleteBeatPattern;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alternative endings',
          style: AppTextTheme.sectionLabel,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final ending in endings) ...[
          SwitchListTile(
            key: Key('songLoopAlternativeEndingToggle-${ending.repeatPass}'),
            value: ending.enabled,
            onChanged: (value) => onEnabledChanged(ending.repeatPass, value),
            title: Text('Ending ${ending.repeatPass}'),
            subtitle: Text('Applies only on pass ${ending.repeatPass}'),
          ),
          if (ending.enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: Key('songLoopAlternativeEndingLength-${ending.repeatPass}'),
              initialValue: ending.lengthBarsText,
              decoration: const InputDecoration(labelText: 'Ending bars'),
              keyboardType: TextInputType.number,
              validator: (value) => validateIntField(
                value: value,
                label: 'Ending bars',
                minimum: SongWriteValidator.minimumAlternativeEndingLengthBars,
              ),
              onChanged: (value) => onLengthChanged(ending.repeatPass, value),
            ),
            const SizedBox(height: AppSpacing.md),
            _AlternativeEndingContentSection(
              ending: ending,
              onAddTempoChange: () => onAddTempoChange(ending.repeatPass),
              onEditTempoChange: (tempoChange) =>
                  onEditTempoChange(ending.repeatPass, tempoChange),
              onDeleteTempoChange: (tempoChangeId) =>
                  onDeleteTempoChange(ending.repeatPass, tempoChangeId),
              onAddSongEvent: () => onAddSongEvent(ending.repeatPass),
              onEditSongEvent: (songEvent) =>
                  onEditSongEvent(ending.repeatPass, songEvent),
              onDeleteSongEvent: (songEventId) =>
                  onDeleteSongEvent(ending.repeatPass, songEventId),
              onAddBeatPattern: () => onAddBeatPattern(ending.repeatPass),
              onEditBeatPattern: (beatPattern) =>
                  onEditBeatPattern(ending.repeatPass, beatPattern),
              onDeleteBeatPattern: (beatPatternId) =>
                  onDeleteBeatPattern(ending.repeatPass, beatPatternId),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _AlternativeEndingContentSection extends StatelessWidget {
  const _AlternativeEndingContentSection({
    required this.ending,
    required this.onAddTempoChange,
    required this.onEditTempoChange,
    required this.onDeleteTempoChange,
    required this.onAddSongEvent,
    required this.onEditSongEvent,
    required this.onDeleteSongEvent,
    required this.onAddBeatPattern,
    required this.onEditBeatPattern,
    required this.onDeleteBeatPattern,
  });

  final _AlternativeEndingDraft ending;
  final VoidCallback onAddTempoChange;
  final void Function(SongTempoChange tempoChange) onEditTempoChange;
  final void Function(String tempoChangeId) onDeleteTempoChange;
  final VoidCallback onAddSongEvent;
  final void Function(SongEvent songEvent) onEditSongEvent;
  final void Function(String songEventId) onDeleteSongEvent;
  final VoidCallback onAddBeatPattern;
  final void Function(SongBarBeatPattern beatPattern) onEditBeatPattern;
  final void Function(String beatPatternId) onDeleteBeatPattern;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlternativeEndingListSection<SongTempoChange>(
          title: 'Time events',
          emptyLabel: 'No time events yet',
          addButtonKey: Key('songLoopAlternativeEndingAddTempoChange-${ending.repeatPass}'),
          onAdd: onAddTempoChange,
          items: ending.tempoChanges,
          itemKey: (tempoChange) =>
              Key('songLoopAlternativeEndingTempoChangeTile-${ending.repeatPass}-${tempoChange.id}'),
          itemTitle: (tempoChange) => 'Bar ${tempoChange.barIndex}',
          itemSubtitle: (tempoChange) =>
              '${tempoChange.bpm} BPM · ${tempoChange.beatsPerBar}/${tempoChange.beatUnit}',
          onEdit: onEditTempoChange,
          onDelete: (tempoChange) => onDeleteTempoChange(tempoChange.id),
        ),
        const SizedBox(height: AppSpacing.md),
        _AlternativeEndingListSection<SongEvent>(
          title: 'Events',
          emptyLabel: 'No events yet',
          addButtonKey: Key('songLoopAlternativeEndingAddSongEvent-${ending.repeatPass}'),
          onAdd: onAddSongEvent,
          items: ending.songEvents,
          itemKey: (songEvent) =>
              Key('songLoopAlternativeEndingSongEventTile-${ending.repeatPass}-${songEvent.id}'),
          itemTitle: (songEvent) => '${songEvent.label} · Bar ${songEvent.barIndex}',
          itemSubtitle: _songEventSubtitle,
          onEdit: onEditSongEvent,
          onDelete: (songEvent) => onDeleteSongEvent(songEvent.id),
        ),
        const SizedBox(height: AppSpacing.md),
        _AlternativeEndingListSection<SongBarBeatPattern>(
          title: 'Beat patterns',
          emptyLabel: 'No beat patterns yet',
          addButtonKey: Key('songLoopAlternativeEndingAddBeatPattern-${ending.repeatPass}'),
          onAdd: onAddBeatPattern,
          items: ending.beatPatterns,
          itemKey: (beatPattern) =>
              Key('songLoopAlternativeEndingBeatPatternTile-${ending.repeatPass}-${beatPattern.id}'),
          itemTitle: (beatPattern) => 'Bar ${beatPattern.barIndex}',
          itemSubtitle: _beatPatternSubtitle,
          onEdit: onEditBeatPattern,
          onDelete: (beatPattern) => onDeleteBeatPattern(beatPattern.id),
        ),
      ],
    );
  }
}

class _AlternativeEndingListSection<T> extends StatelessWidget {
  const _AlternativeEndingListSection({
    required this.title,
    required this.emptyLabel,
    required this.addButtonKey,
    required this.onAdd,
    required this.items,
    required this.itemKey,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String emptyLabel;
  final Key addButtonKey;
  final VoidCallback onAdd;
  final List<T> items;
  final Key Function(T item) itemKey;
  final String Function(T item) itemTitle;
  final String Function(T item) itemSubtitle;
  final void Function(T item) onEdit;
  final void Function(T item) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextTheme.sectionLabel,
              ),
            ),
            TDButton(
              key: addButtonKey,
              label: 'Add',
              icon: Icons.add,
              variant: TDButtonVariant.secondary,
              onPressed: onAdd,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Text(
            emptyLabel,
            style: AppTextTheme.bodySecondary,
          )
        else
          ...items.map(
            (item) => ListTile(
              key: itemKey(item),

              title: Text(itemTitle(item)),
              subtitle: Text(itemSubtitle(item)),
              trailing: PopupMenuButton<_AlternativeEndingItemAction>(
                onSelected: (action) {
                  switch (action) {
                    case _AlternativeEndingItemAction.edit:
                      onEdit(item);
                    case _AlternativeEndingItemAction.delete:
                      onDelete(item);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _AlternativeEndingItemAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: _AlternativeEndingItemAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _AlternativeEndingItemAction { edit, delete }

class _AlternativeEndingDraft {
  const _AlternativeEndingDraft({
    required this.id,
    required this.repeatPass,
    required this.enabled,
    required this.lengthBarsText,
    required this.tempoChanges,
    required this.songEvents,
    required this.beatPatterns,
  });

  factory _AlternativeEndingDraft.fromExisting({
    required int repeatPass,
    required SongLoopAlternativeEnding? existing,
  }) {
    final existingEnding = _existingEndingForPass(
      existing == null ? const [] : [existing],
      repeatPass,
    );
    return _AlternativeEndingDraft(
      id: existingEnding?.id ?? const Uuid().v4(),
      repeatPass: repeatPass,
      enabled: existingEnding != null,
      lengthBarsText: existingEnding?.lengthBars.toString() ?? '1',
      tempoChanges: existingEnding?.tempoChanges ?? const [],
      songEvents: existingEnding?.songEvents ?? const [],
      beatPatterns: existingEnding?.beatPatterns ?? const [],
    );
  }

  final String id;
  final int repeatPass;
  final bool enabled;
  final String lengthBarsText;
  final List<SongTempoChange> tempoChanges;
  final List<SongEvent> songEvents;
  final List<SongBarBeatPattern> beatPatterns;

  _AlternativeEndingDraft copyWith({
    bool? enabled,
    String? lengthBarsText,
    List<SongTempoChange>? tempoChanges,
    List<SongEvent>? songEvents,
    List<SongBarBeatPattern>? beatPatterns,
  }) {
    return _AlternativeEndingDraft(
      id: id,
      repeatPass: repeatPass,
      enabled: enabled ?? this.enabled,
      lengthBarsText: lengthBarsText ?? this.lengthBarsText,
      tempoChanges: tempoChanges ?? this.tempoChanges,
      songEvents: songEvents ?? this.songEvents,
      beatPatterns: beatPatterns ?? this.beatPatterns,
    );
  }
}

class _AlternativeEndingConfig {
  const _AlternativeEndingConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
  });

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
}

SongLoopAlternativeEnding? _existingEndingForPass(
  List<SongLoopAlternativeEnding> endings,
  int repeatPass,
) {
  for (final ending in endings) {
    if (ending.repeatPass == repeatPass) {
      return ending;
    }
  }
  return null;
}

class _SongEventDialog extends StatefulWidget {
  const _SongEventDialog({
    required this.initialValue,
    required this.maximumEndBar,
    required this.createSongEvent,
    required this.validateIntField,
    required this.linkedAudioPicker,
    required this.linkedAudioImportService,
    required this.linkedAudioFileStorage,
    required this.audioEngine,
    required this.cueVolumeFactor,
  });

  final SongEvent? initialValue;
  final int maximumEndBar;
  final SongEvent Function({
    required int barIndex,
    required String label,
    required AudioCue? audioCue,
    required int audioCueBarsBefore,
  }) createSongEvent;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;
  final LinkedAudioPicker linkedAudioPicker;
  final LinkedAudioImportService linkedAudioImportService;
  final LinkedAudioFileStorage linkedAudioFileStorage;
  final IAudioEngine audioEngine;
  final double cueVolumeFactor;

  @override
  State<_SongEventDialog> createState() => _SongEventDialogState();
}

class _SongEventDialogState extends State<_SongEventDialog> {
  static final Logger _logger = Logger('_SongEventDialogState');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barIndexController;
  late final TextEditingController _labelController;
  late final TextEditingController _audioCueBarsBeforeController;
  late final TextEditingController _voiceTextController;
  late final TextEditingController _customFilePathController;
  late final TextEditingController _customFileDisplayNameController;
  late int _volumePercent;
  AudioCueType? _audioCueType;
  String? _selectedVoiceIdentifier;
  List<TextToSpeechVoice> _availableVoices = [];
  String? _voiceLoadError;
  bool _isPreviewingVoice = false;
  bool _isPreviewingCustomFile = false;

  @override
  void initState() {
    super.initState();
    final audioCue = widget.initialValue?.audioCue;
    _barIndexController = TextEditingController(
      text: widget.initialValue?.barIndex.toString() ?? '',
    );
    _labelController = TextEditingController(
      text: widget.initialValue?.label ?? '',
    );
    _audioCueBarsBeforeController = TextEditingController(
      text: widget.initialValue?.audioCueBarsBefore.toString() ?? '0',
    );
    _voiceTextController = TextEditingController(
      text: audioCue?.voiceText ?? '',
    );
    _customFilePathController = TextEditingController(
      text: audioCue?.customFilePath ?? '',
    );
    _customFileDisplayNameController = TextEditingController(
      text: audioCue?.customFileDisplayName ?? '',
    );
    _volumePercent = audioCue?.volumePercent ?? 100;
    _audioCueType = audioCue?.type;
    _selectedVoiceIdentifier = audioCue?.voiceIdentifier;
    _loadAvailableVoices();
  }

  @override
  void dispose() {
    _barIndexController.dispose();
    _labelController.dispose();
    _audioCueBarsBeforeController.dispose();
    _voiceTextController.dispose();
    _customFilePathController.dispose();
    _customFileDisplayNameController.dispose();
    if (_isPreviewingVoice || _isPreviewingCustomFile) {
      unawaited(widget.audioEngine.stop());
    }
    super.dispose();
  }

  Future<void> _loadAvailableVoices() async {
    try {
      final voices = await widget.audioEngine.getAvailableVoices();
      if (!mounted) return;
      final knownIdentifiers =
          voices.map((v) => v.identifier).whereType<String>().toSet();
      setState(() {
        _availableVoices = voices;
        _voiceLoadError = null;
        // Reset to default if the saved voice is no longer available.
        if (_selectedVoiceIdentifier != null &&
            !knownIdentifiers.contains(_selectedVoiceIdentifier)) {
          _selectedVoiceIdentifier = null;
        }
      });
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to load available voices.',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _voiceLoadError =
            'Voice cues are not available on this device.';
      });
    }
  }

  Future<void> _previewVoice() async {
    final text = _voiceTextController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isPreviewingVoice = true;
    });

    try {
      await widget.audioEngine.speakCue(
        text,
        voiceIdentifier: _selectedVoiceIdentifier,
      );
    } catch (error, stackTrace) {
      _logger.warning('Failed to preview voice cue.', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice preview failed. TTS is not available.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPreviewingVoice = false;
        });
      }
    }
  }

  Future<void> _stopVoicePreview() async {
    await widget.audioEngine.stop();
    setState(() {
      _isPreviewingVoice = false;
    });
  }

  Future<void> _previewCustomFile() async {
    final filePath = _customFilePathController.text.trim();
    if (filePath.isEmpty) return;

    setState(() {
      _isPreviewingCustomFile = true;
    });

    try {
      await widget.audioEngine.playLinkedAudio(
        filePath,
        offset: Duration.zero,
        volume: (_volumePercent / 100) * widget.cueVolumeFactor,
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to preview custom file cue.',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPreviewingCustomFile = false;
        });
      }
    }
  }

  Future<void> _stopCustomFilePreview() async {
    await widget.audioEngine.stop();
    setState(() {
      _isPreviewingCustomFile = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: Text(widget.initialValue == null ? 'Add song event' : 'Edit song event'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('songEventBarIndexField'),
                controller: _barIndexController,
                decoration: const InputDecoration(labelText: 'Bar index'),
                keyboardType: TextInputType.number,
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Bar index',
                  minimum: SongWriteValidator.minimumBarIndex,
                  maximum: widget.maximumEndBar,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('songEventLabelField'),
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Label'),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    return null;
                  }
                  return 'Label must not be empty';
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<AudioCueType?>(
                key: const Key('songEventAudioCueTypeField'),
                initialValue: _audioCueType,
                decoration: const InputDecoration(labelText: 'Audio cue'),
                items: [
                  const DropdownMenuItem<AudioCueType?>(
                    value: null,
                    child: Text('None'),
                  ),
                  ...AudioCueType.values.map(
                    (type) => DropdownMenuItem<AudioCueType?>(
                      value: type,
                      child: Text(_audioCueTypeLabel(type)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _audioCueType = value;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('songEventBarsBeforeField'),
                controller: _audioCueBarsBeforeController,
                decoration: const InputDecoration(labelText: 'Bars before'),
                keyboardType: TextInputType.number,
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Bars before',
                  minimum: SongWriteValidator.minimumAudioCueBarsBefore,
                ),
              ),
              if (_audioCueType == AudioCueType.voice) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('songEventVoiceTextField'),
                  controller: _voiceTextController,
                  decoration: const InputDecoration(labelText: 'Voice text'),
                  validator: (value) {
                    if (_audioCueType != AudioCueType.voice) {
                      return null;
                    }
                    if (value != null && value.trim().isNotEmpty) {
                      return null;
                    }
                    return 'Voice text must not be empty';
                  },
                ),
                if (_voiceLoadError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _voiceLoadError!,
                    style: AppTextTheme.bodySecondary.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ] else if (_availableVoices.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String?>(
                    key: const Key('songEventVoiceIdentifierField'),
                    initialValue: _selectedVoiceIdentifier,
                    decoration:
                        const InputDecoration(labelText: 'Voice'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Default'),
                      ),
                      ..._availableVoices.map(
                        (voice) => DropdownMenuItem<String?>(
                          value: voice.identifier,
                          child: Text(voice.displayLabel),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedVoiceIdentifier = value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  key: const Key('songEventVoicePreviewRow'),
                  children: [
                    IconButton(
                      key: const Key('songEventVoicePreviewButton'),
                      icon: Icon(
                        _isPreviewingVoice
                            ? Icons.stop
                            : Icons.play_arrow,
                      ),
                      onPressed: _voiceTextController.text.trim().isEmpty
                          ? null
                          : _isPreviewingVoice
                              ? _stopVoicePreview
                              : _previewVoice,
                      tooltip: _isPreviewingVoice
                          ? 'Stop preview'
                          : 'Preview voice',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _isPreviewingVoice
                          ? 'Playing...'
                          : 'Preview voice',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              if (_audioCueType == AudioCueType.customFile) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  key: const Key('songEventCustomFilePickerRow'),
                  children: [
                    Expanded(
                      child: Text(
                        _customFileDisplayNameController.text.isNotEmpty
                            ? _customFileDisplayNameController.text
                            : 'No file selected',
                        style: TextStyle(
                          color: _customFileDisplayNameController.text.isNotEmpty
                              ? null
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TDButton(
                      key: const Key('songEventPickCustomFileButton'),
                      label: 'Pick file',
                      icon: Icons.folder_open,
                      variant: TDButtonVariant.secondary,
                      onPressed: _pickCustomFile,
                    ),
                  ],
                ),
                if (_audioCueType == AudioCueType.customFile &&
                    _customFilePathController.text.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Custom file path must not be empty',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_customFilePathController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    key: const Key('songEventCustomFilePreviewRow'),
                    children: [
                      IconButton(
                        key: const Key('songEventCustomFilePreviewButton'),
                        icon: Icon(
                          _isPreviewingCustomFile
                              ? Icons.stop
                              : Icons.play_arrow,
                        ),
                        onPressed: _isPreviewingCustomFile
                            ? _stopCustomFilePreview
                            : _previewCustomFile,
                        tooltip: _isPreviewingCustomFile
                            ? 'Stop preview'
                            : 'Preview file',
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _isPreviewingCustomFile
                            ? 'Playing...'
                            : 'Preview file',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickCustomFile() async {
    final pickedFile = await widget.linkedAudioPicker.pickAudioFile();
    if (pickedFile == null) {
      return;
    }

    final importedFile = await widget.linkedAudioImportService
        .importPickedAudioFile(pickedFile);

    // Old file cleanup is handled by the parent screen after a successful
    // save — not here, because the user may cancel the dialog.
    setState(() {
      _customFilePathController.text = importedFile.filePath;
      _customFileDisplayNameController.text = importedFile.displayName;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_audioCueType == AudioCueType.customFile &&
        _customFilePathController.text.trim().isEmpty) {
      return;
    }

    Navigator.pop(
      context,
      widget.initialValue == null
          ? widget.createSongEvent(
              barIndex: int.parse(_barIndexController.text),
              label: _labelController.text.trim(),
              audioCue: _buildAudioCue(),
              audioCueBarsBefore: int.parse(_audioCueBarsBeforeController.text),
            )
          : SongEvent(
              id: widget.initialValue!.id,
              barIndex: int.parse(_barIndexController.text),
              label: _labelController.text.trim(),
              audioCue: _buildAudioCue(),
              audioCueBarsBefore: int.parse(_audioCueBarsBeforeController.text),
            ),
    );
  }

  AudioCue? _buildAudioCue() {
    final type = _audioCueType;
    if (type == null) {
      return null;
    }

    return AudioCue(
      type: type,
      voiceText: type == AudioCueType.voice ? _voiceTextController.text.trim() : null,
      voiceIdentifier:
          type == AudioCueType.voice ? _selectedVoiceIdentifier : null,
      customFilePath:
          type == AudioCueType.customFile ? _customFilePathController.text.trim() : null,
      customFileDisplayName: type == AudioCueType.customFile
          ? _customFileDisplayNameController.text.trim()
          : null,
      volumePercent: _volumePercent,
    );
  }

  String _audioCueTypeLabel(AudioCueType type) {
    switch (type) {
      case AudioCueType.intervalSignal:
        return 'Interval signal';
      case AudioCueType.maxSignal:
        return 'Max signal';
      case AudioCueType.lowPulse:
        return 'Low pulse';
      case AudioCueType.midPulse:
        return 'Mid pulse';
      case AudioCueType.highPulse:
        return 'High pulse';
      case AudioCueType.voice:
        return 'Voice';
      case AudioCueType.customFile:
        return 'Custom file';
    }
  }
}

class _TempoChangeDialogState extends State<_TempoChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barIndexController;
  late final TextEditingController _bpmController;
  late int _bpm;
  late int _beatsPerBar;
  late int _beatUnit;

  @override
  void initState() {
    super.initState();
    _barIndexController = TextEditingController(
      text: widget.initialValue?.barIndex.toString() ?? '',
    );
    _bpm = widget.initialValue?.bpm ?? widget.initialBpm;
    _bpmController = TextEditingController(text: _bpm.toString());
    _beatsPerBar =
        widget.initialValue?.beatsPerBar ?? widget.initialBeatsPerBar;
    _beatUnit = widget.initialValue?.beatUnit ?? widget.defaultBeatUnit;
  }

  @override
  void dispose() {
    _barIndexController.dispose();
    _bpmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: Text(
        widget.initialValue == null ? 'Add tempo change' : 'Edit tempo change',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('tempoChangeBarIndexField'),
                controller: _barIndexController,
                decoration: const InputDecoration(labelText: 'Bar index'),
                keyboardType: TextInputType.number,
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Bar index',
                  minimum: SongWriteValidator.minimumBarIndex,
                  maximum: widget.maximumEndBar,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SongTempoField(
                sliderKey: const Key('tempoChangeBpmSlider'),
                textFieldKey: const Key('tempoChangeBpmField'),
                label: 'BPM',
                bpm: _bpm,
                controller: _bpmController,
                onChanged: (value) {
                  setState(() {
                    _bpm = value;
                    _bpmController.text = '$value';
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _SongMeterSelectorRow(
                beatsPerBarKey: const Key('tempoChangeBeatsPerBarField'),
                beatUnitKey: const Key('tempoChangeBeatUnitField'),
                beatsPerBar: _beatsPerBar,
                beatUnit: _beatUnit,
                onBeatsPerBarChanged: (value) {
                  setState(() {
                    _beatsPerBar = value;
                  });
                },
                onBeatUnitChanged: (value) {
                  setState(() {
                    _beatUnit = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.pop(
      context,
      widget.initialValue == null
          ? widget.createTempoChange(
              barIndex: int.parse(_barIndexController.text),
              bpm: _bpm,
              beatsPerBar: _beatsPerBar,
              beatUnit: _beatUnit,
            )
          : SongTempoChange(
              id: widget.initialValue!.id,
              barIndex: int.parse(_barIndexController.text),
              bpm: _bpm,
              beatsPerBar: _beatsPerBar,
              beatUnit: _beatUnit,
            ),
    );
  }
}

class _BeatPatternDialog extends StatefulWidget {
  const _BeatPatternDialog({
    required this.initialValue,
    required this.defaultBeatsPerBar,
    required this.maximumEndBar,
    required this.createBeatPattern,
    required this.validateIntField,
    this.beatsPerBarResolver,
  });

  final SongBarBeatPattern? initialValue;
  final int defaultBeatsPerBar;
  final int maximumEndBar;
  final SongBarBeatPattern Function({
    required int barIndex,
    required List<AccentLevel> accents,
    required Subdivision subdivision,
    required int? repeatPass,
  }) createBeatPattern;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;
  final int Function(int barIndex)? beatsPerBarResolver;

  @override
  State<_BeatPatternDialog> createState() => _BeatPatternDialogState();
}

class _BeatPatternDialogState extends State<_BeatPatternDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barIndexController;
  late final TextEditingController _repeatPassController;
  late List<AccentLevel> _accents;
  late Subdivision _subdivision;

  @override
  void initState() {
    super.initState();
    _barIndexController = TextEditingController(
      text: widget.initialValue?.barIndex.toString() ?? '',
    );
    _repeatPassController = TextEditingController(
      text: widget.initialValue?.repeatPass?.toString() ?? '',
    );
    _accents = widget.initialValue?.accents.toList() ??
        _defaultAccents(_resolvedBeatsPerBar(_initialBarIndex));
    _subdivision = widget.initialValue?.subdivision ?? Subdivision.one;
  }

  @override
  void dispose() {
    _barIndexController.dispose();
    _repeatPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: Text(
        widget.initialValue == null ? 'Add beat pattern' : 'Edit beat pattern',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('songBeatPatternBarIndexField'),
                controller: _barIndexController,
                decoration: const InputDecoration(labelText: 'Bar index'),
                keyboardType: TextInputType.number,
                onChanged: (_) => _handleBarIndexChanged(),
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Bar index',
                  minimum: SongWriteValidator.minimumBarIndex,
                  maximum: widget.maximumEndBar,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('songBeatPatternRepeatPassField'),
                controller: _repeatPassController,
                decoration: const InputDecoration(
                  labelText: 'Repeat pass (optional)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return null;
                  }

                  return widget.validateIntField(
                    value: value,
                    label: 'Repeat pass',
                    minimum: SongWriteValidator.minimumRepeatCount,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<Subdivision>(
                key: const Key('songBeatPatternSubdivisionField'),
                initialValue: _subdivision,
                decoration: const InputDecoration(labelText: 'Subdivision'),
                items: Subdivision.values
                    .map(
                      (subdivision) => DropdownMenuItem(
                        value: subdivision,
                        child: Text(subdivision.displayLabel),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _subdivision = value;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Accent grid',
                style: AppTextTheme.heading3,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _accents.length; index++)
                    FilterChip(
                      key: Key('songBeatPatternAccentChip-$index'),
                      label: Text(
                        'Beat ${index + 1}: '
                        '${_accentShortLabelFor(_accents[index])}',
                      ),
                      selected: _accents[index] != AccentLevel.mute,
                      onSelected: (_) => _cycleAccent(index),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _cycleAccent(int index) {
    setState(() {
      _accents = [
        for (var currentIndex = 0; currentIndex < _accents.length; currentIndex++)
          if (currentIndex == index)
            _nextAccent(_accents[currentIndex])
          else
            _accents[currentIndex],
      ];
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final repeatPassText = _repeatPassController.text.trim();
    final repeatPass = repeatPassText.isEmpty ? null : int.parse(repeatPassText);

    Navigator.pop(
      context,
      widget.initialValue == null
          ? widget.createBeatPattern(
              barIndex: int.parse(_barIndexController.text),
              accents: List.unmodifiable(_accents),
              subdivision: _subdivision,
              repeatPass: repeatPass,
            )
          : SongBarBeatPattern(
              id: widget.initialValue!.id,
              barIndex: int.parse(_barIndexController.text),
              accents: List.unmodifiable(_accents),
              subdivision: _subdivision,
              repeatPass: repeatPass,
            ),
    );
  }

  int get _initialBarIndex => widget.initialValue?.barIndex ?? 1;

  void _handleBarIndexChanged() {
    setState(() {
      _accents = _resizeAccents(
        _accents,
        _resolvedBeatsPerBar(int.tryParse(_barIndexController.text) ?? _initialBarIndex),
      );
    });
  }

  int _resolvedBeatsPerBar(int barIndex) {
    final resolver = widget.beatsPerBarResolver;
    if (resolver == null) {
      return widget.defaultBeatsPerBar;
    }
    return resolver(barIndex);
  }

  List<AccentLevel> _resizeAccents(
    List<AccentLevel> accents,
    int targetBeatsPerBar,
  ) {
    if (targetBeatsPerBar <= 0) {
      return const <AccentLevel>[AccentLevel.high];
    }
    if (accents.length == targetBeatsPerBar) {
      return accents;
    }
    if (accents.length > targetBeatsPerBar) {
      return accents.take(targetBeatsPerBar).toList(growable: false);
    }
    return [
      ...accents,
      for (var index = accents.length; index < targetBeatsPerBar; index += 1)
        index == 0 ? AccentLevel.high : AccentLevel.normal,
    ];
  }

  List<AccentLevel> _defaultAccents(int beatsPerBar) {
    return [
      AccentLevel.high,
      for (var index = 1; index < beatsPerBar; index++) AccentLevel.normal,
    ];
  }

  AccentLevel _nextAccent(AccentLevel accent) {
    switch (accent) {
      case AccentLevel.high:
        return AccentLevel.normal;
      case AccentLevel.normal:
        return AccentLevel.low;
      case AccentLevel.low:
        return AccentLevel.mute;
      case AccentLevel.mute:
        return AccentLevel.high;
    }
  }

}

class _InlineLinkedAudioEditor extends ConsumerStatefulWidget {
  const _InlineLinkedAudioEditor({
    required this.linkedAudio,
    required this.onChanged,
    required this.validateIntField,
  });

  final LinkedAudioFile linkedAudio;
  final ValueChanged<LinkedAudioFile> onChanged;
  final String? Function({
    required String? value,
    required String label,
    required int minimum,
    int? maximum,
  }) validateIntField;

  @override
  ConsumerState<_InlineLinkedAudioEditor> createState() =>
      _InlineLinkedAudioEditorState();
}

class _InlineLinkedAudioEditorState
    extends ConsumerState<_InlineLinkedAudioEditor> {
  static final Logger _logger = Logger('_InlineLinkedAudioEditorState');
  static const int _defaultMaximumOffsetMilliseconds = 999999;

  late final TextEditingController _offsetMillisecondsController;
  late final IAudioEngine _audioEngine;
  _LinkedAudioWaveformData? _waveformData;
  String? _loadedFilePath;
  String? _waveformError;
  bool _isLoadingWaveform = false;
  bool _isPreviewing = false;
  Timer? _previewResetTimer;

  @override
  void initState() {
    super.initState();
    _audioEngine = ref.read(audioEngineProvider);
    _offsetMillisecondsController = TextEditingController();
    _syncControllers(widget.linkedAudio);
    unawaited(_preloadLinkedAudio(widget.linkedAudio));
    _loadWaveform(widget.linkedAudio);
  }

  @override
  void didUpdateWidget(covariant _InlineLinkedAudioEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkedAudio.filePath != widget.linkedAudio.filePath) {
      _scheduleControllerSync(widget.linkedAudio);
      unawaited(_preloadLinkedAudio(widget.linkedAudio));
      _loadWaveform(widget.linkedAudio);
    } else {
      _scheduleControllerSync(widget.linkedAudio);
    }
  }

  @override
  void dispose() {
    _previewResetTimer?.cancel();
    if (_isPreviewing) {
      unawaited(_audioEngine.stop());
    }
    _offsetMillisecondsController.dispose();
    super.dispose();
  }

  void _syncControllers(LinkedAudioFile linkedAudio) {
    final offsetText = linkedAudio.offsetMilliseconds.toString();
    if (_offsetMillisecondsController.text != offsetText) {
      _offsetMillisecondsController.text = offsetText;
    }
  }

  void _scheduleControllerSync(LinkedAudioFile linkedAudio) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncControllers(linkedAudio);
    });
  }

  Future<void> _loadWaveform(LinkedAudioFile linkedAudio) async {
    final resolvedLinkedAudio = await _repairLinkedAudioPath(linkedAudio);
    final filePath = resolvedLinkedAudio.filePath;
    if (_loadedFilePath == filePath && _waveformData != null) {
      return;
    }

    setState(() {
      _loadedFilePath = filePath;
      _isLoadingWaveform = true;
      _waveformError = null;
      _waveformData = null;
    });

    try {
      final clip = await ref.read(linkedAudioClipLoaderProvider).loadClip(
            resolvedLinkedAudio,
          );
      final waveformData = _LinkedAudioWaveformData.fromClip(clip);
      if (!mounted || _loadedFilePath != filePath) {
        return;
      }

      final clampedOffset = _clampOffsetMilliseconds(
        resolvedLinkedAudio.offsetMilliseconds,
        waveformData.maximumOffsetMilliseconds,
      );
      if (clampedOffset != resolvedLinkedAudio.offsetMilliseconds) {
        widget.onChanged(
          LinkedAudioFile(
            filePath: resolvedLinkedAudio.filePath,
            displayName: resolvedLinkedAudio.displayName,

            offsetMilliseconds: clampedOffset,
            volumePercent: resolvedLinkedAudio.volumePercent,
            playInLiveMode: resolvedLinkedAudio.playInLiveMode,
          ),
        );
      }

      setState(() {
        _waveformData = waveformData;
        _isLoadingWaveform = false;
      });
    } catch (error, stackTrace) {
      _logger.warning('Failed to load linked audio waveform.', error, stackTrace);
      if (!mounted || _loadedFilePath != filePath) {
        return;
      }
      setState(() {
        _waveformError = 'Could not load waveform.';
        _isLoadingWaveform = false;
      });
    }
  }

  Future<void> _preloadLinkedAudio(LinkedAudioFile linkedAudio) async {
    final resolvedLinkedAudio = await _repairLinkedAudioPath(linkedAudio);
    if (!mounted) {
      return;
    }

    try {
      await _audioEngine.initialize();
      await _audioEngine.preloadLinkedAudio(resolvedLinkedAudio.filePath);
    } catch (error, stackTrace) {
      _logger.warning('Failed to preload linked audio for song editor.', error, stackTrace);
    }
  }

  Future<void> _togglePreview() async {
    final audioEngine = _audioEngine;
    if (_isPreviewing) {
      await _stopPreview(audioEngine: audioEngine);
      return;
    }

    final resolvedLinkedAudio = await _repairLinkedAudioPath(widget.linkedAudio);
    if (!mounted) {
      return;
    }
    final offsetMs = int.tryParse(_offsetMillisecondsController.text) ??
        resolvedLinkedAudio.offsetMilliseconds;
    final songVolumePercent =
        ref.read(audioMixerControllerProvider).songVolumePercent;

    await audioEngine.stop();
    setState(() {
      _isPreviewing = true;
    });

    try {
      await audioEngine.playLinkedAudio(
        resolvedLinkedAudio.filePath,
        offset: Duration(milliseconds: offsetMs),
        volume: songVolumePercent / AudioMixerState.maximumVolumePercent,
      );
      _schedulePreviewReset(offsetMs);
    } catch (error, stackTrace) {
      _logger.warning('Failed to preview linked audio.', error, stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not preview linked audio: $error')),
      );
      setState(() {
        _isPreviewing = false;
      });
    }
  }

  Future<void> _stopPreview({IAudioEngine? audioEngine}) async {
    _previewResetTimer?.cancel();
    final IAudioEngine resolvedAudioEngine = audioEngine ?? _audioEngine;
    await resolvedAudioEngine.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isPreviewing = false;
    });
  }

  void _schedulePreviewReset(int offsetMilliseconds) {
    _previewResetTimer?.cancel();
    final waveformData = _waveformData;
    if (waveformData == null) {
      return;
    }

    final remainingMilliseconds =
        waveformData.maximumOffsetMilliseconds - offsetMilliseconds;
    if (remainingMilliseconds <= 0) {
      if (mounted) {
        setState(() {
          _isPreviewing = false;
        });
      }
      return;
    }

    _previewResetTimer = Timer(
      Duration(milliseconds: remainingMilliseconds),
      () {
        if (!mounted) {
          return;
        }
        setState(() {
          _isPreviewing = false;
        });
      },
    );
  }

  void _setOffsetMilliseconds(int offsetMilliseconds) {
    final maximumOffset = _waveformData?.maximumOffsetMilliseconds ??
        _defaultMaximumOffsetMilliseconds;
    final clampedOffset =
        _clampOffsetMilliseconds(offsetMilliseconds, maximumOffset);
    _offsetMillisecondsController.text = clampedOffset.toString();
    widget.onChanged(
      LinkedAudioFile(
        filePath: widget.linkedAudio.filePath,
        displayName: widget.linkedAudio.displayName,

        offsetMilliseconds: clampedOffset,
        volumePercent: widget.linkedAudio.volumePercent,
        playInLiveMode: widget.linkedAudio.playInLiveMode,
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _adjustOffset(int delta) {
    final current =
        int.tryParse(_offsetMillisecondsController.text) ?? 0;
    _setOffsetMilliseconds(current + delta);
  }

  int _clampOffsetMilliseconds(int value, int maximumOffsetMilliseconds) {
    return value.clamp(
      SongWriteValidator.minimumLinkedAudioOffsetMilliseconds,
      maximumOffsetMilliseconds,
    );
  }

  Future<LinkedAudioFile> _repairLinkedAudioPath(
    LinkedAudioFile linkedAudio,
  ) async {
    final repairedLinkedAudio = await ref
        .read(linkedAudioPathRepairServiceProvider)
        .repairIfNeeded(linkedAudio);
    if (!mounted) {
      return repairedLinkedAudio;
    }
    if (repairedLinkedAudio.filePath != linkedAudio.filePath) {
      widget.onChanged(repairedLinkedAudio);
    }
    return repairedLinkedAudio;
  }

  @override
  Widget build(BuildContext context) {
    final waveformData = _waveformData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Offset',
                style: AppTextTheme.heading3,
              ),
            ),
            TDButton(
              key: const Key('songLinkedAudioPreviewButton'),
              label: _isPreviewing ? 'Stop' : 'Preview',
              icon: _isPreviewing ? Icons.stop : Icons.play_arrow,
              variant: TDButtonVariant.secondary,
              onPressed: _togglePreview,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _LinkedAudioWaveformEditor(
          key: const Key('songLinkedAudioWaveformEditor'),
          waveformData: waveformData,
          currentOffsetMilliseconds: widget.linkedAudio.offsetMilliseconds,
          isLoading: _isLoadingWaveform,
          errorText: _waveformError,
          onOffsetChanged: _setOffsetMilliseconds,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _OffsetStepButton(
              key: const Key('songLinkedAudioOffsetMinus100Button'),
              label: '−100',
              onPressed: () => _adjustOffset(-100),
            ),
            const SizedBox(width: AppSpacing.xs),
            _OffsetStepButton(
              key: const Key('songLinkedAudioOffsetMinus10Button'),
              label: '−10',
              onPressed: () => _adjustOffset(-10),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                key: const Key('songLinkedAudioOffsetField'),
                controller: _offsetMillisecondsController,
                decoration: const InputDecoration(
                  labelText: 'Offset (ms)',
                ),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                validator: (value) => widget.validateIntField(
                  value: value,
                  label: 'Offset',
                  minimum:
                      SongWriteValidator.minimumLinkedAudioOffsetMilliseconds,
                  maximum: waveformData?.maximumOffsetMilliseconds,
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    _setOffsetMilliseconds(parsed);
                  }
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _OffsetStepButton(
              key: const Key('songLinkedAudioOffsetPlus10Button'),
              label: '+10',
              onPressed: () => _adjustOffset(10),
            ),
            const SizedBox(width: AppSpacing.xs),
            _OffsetStepButton(
              key: const Key('songLinkedAudioOffsetPlus100Button'),
              label: '+100',
              onPressed: () => _adjustOffset(100),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          key: const Key('songLinkedAudioPlayInLiveModeSwitch'),
          contentPadding: EdgeInsets.zero,
          value: widget.linkedAudio.playInLiveMode,
          onChanged: (value) {
            widget.onChanged(
              LinkedAudioFile(
                filePath: widget.linkedAudio.filePath,
                displayName: widget.linkedAudio.displayName,
                offsetMilliseconds: widget.linkedAudio.offsetMilliseconds,
                volumePercent: widget.linkedAudio.volumePercent,
                playInLiveMode: value,
              ),
            );
          },
          title: const Text('Play in live mode'),
        ),
      ],
    );
  }
}

class _LinkedAudioWaveformEditor extends StatefulWidget {
  static const double waveformHeight = 132;
  static const double cursorWidth = 3;
  static const double cursorGlowWidth = 11;
  static const double cursorHeight = 104;
  static const double dragSensitivity = 0.35;
  static const int maximumVisibleDurationMilliseconds = 1800;

  const _LinkedAudioWaveformEditor({
    super.key,
    required this.waveformData,
    required this.currentOffsetMilliseconds,
    required this.isLoading,
    required this.errorText,
    required this.onOffsetChanged,
  });

  final _LinkedAudioWaveformData? waveformData;
  final int currentOffsetMilliseconds;
  final bool isLoading;
  final String? errorText;
  final ValueChanged<int> onOffsetChanged;

  @override
  State<_LinkedAudioWaveformEditor> createState() =>
      _LinkedAudioWaveformEditorState();
}

class _LinkedAudioWaveformEditorState extends State<_LinkedAudioWaveformEditor> {
  int? _dragStartOffsetMilliseconds;
  double _accumulatedDragDx = 0;

  int _visibleDurationMilliseconds(_LinkedAudioWaveformData waveformData) {
    return waveformData.maximumOffsetMilliseconds
        .clamp(1, _LinkedAudioWaveformEditor.maximumVisibleDurationMilliseconds)
        .clamp(1, waveformData.maximumOffsetMilliseconds);
  }

  int _dragOffsetMilliseconds({
    required _LinkedAudioWaveformData waveformData,
    required double width,
    required double accumulatedDx,
  }) {
    final dragStartOffsetMilliseconds = _dragStartOffsetMilliseconds ??
        widget.currentOffsetMilliseconds;
    final visibleDuration = _visibleDurationMilliseconds(waveformData);
    final deltaRatio =
        (accumulatedDx / width) * _LinkedAudioWaveformEditor.dragSensitivity;
    return (dragStartOffsetMilliseconds + (visibleDuration * deltaRatio))
        .round()
        .clamp(
          SongWriteValidator.minimumLinkedAudioOffsetMilliseconds,
          waveformData.maximumOffsetMilliseconds,
        );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final waveformData = widget.waveformData;

        final waveformCanvas = SizedBox(
          height: _LinkedAudioWaveformEditor.waveformHeight,
          width: constraints.maxWidth,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _LinkedAudioWaveformPainter(
                  waveformData: waveformData,
                  currentOffsetMilliseconds: widget.currentOffsetMilliseconds,
                ),
              ),
              if (widget.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (widget.errorText != null)
                Center(
                  child: Text(
                    widget.errorText!,
                    style: AppTextTheme.bodySecondary,
                  ),
                ),
              IgnorePointer(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: _LinkedAudioWaveformEditor.cursorGlowWidth,
                        height: _LinkedAudioWaveformEditor.cursorHeight,
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(
                            _LinkedAudioWaveformEditor.cursorGlowWidth,
                          ),
                        ),
                      ),
                      Container(
                        key: const Key('songLinkedAudioWaveformCursor'),
                        width: _LinkedAudioWaveformEditor.cursorWidth,
                        height: _LinkedAudioWaveformEditor.cursorHeight,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary,
                          borderRadius: BorderRadius.circular(
                            _LinkedAudioWaveformEditor.cursorWidth,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        if (waveformData == null) {
          return waveformCanvas;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            _dragStartOffsetMilliseconds = widget.currentOffsetMilliseconds;
            _accumulatedDragDx = 0;
          },
          onHorizontalDragUpdate: (details) {
            final width = constraints.maxWidth;
            if (width <= 0) {
              return;
            }
            _accumulatedDragDx += details.delta.dx;
            widget.onOffsetChanged(
              _dragOffsetMilliseconds(
                waveformData: waveformData,
                width: width,
                accumulatedDx: _accumulatedDragDx,
              ),
            );
          },
          onHorizontalDragEnd: (_) {
            _dragStartOffsetMilliseconds = null;
            _accumulatedDragDx = 0;
          },
          onHorizontalDragCancel: () {
            _dragStartOffsetMilliseconds = null;
            _accumulatedDragDx = 0;
          },
          child: waveformCanvas,
        );
      },
    );
  }
}

class _LinkedAudioWaveformData {
  const _LinkedAudioWaveformData({
    required this.amplitudes,
    required this.maximumOffsetMilliseconds,
  });

  factory _LinkedAudioWaveformData.fromClip(ExportAudioClip clip) {
    const int bucketCount = 4800;
    final frameCount = clip.samples.length ~/ clip.channelCount;
    final totalMilliseconds = (frameCount * 1000 / clip.sampleRate).round();
    final maximumOffsetMilliseconds =
        totalMilliseconds > 0 ? totalMilliseconds : 0;
    final bucketSize = frameCount <= bucketCount
        ? 1
        : (frameCount / bucketCount).ceil();
    final amplitudes = <double>[];

    for (var frameStart = 0; frameStart < frameCount; frameStart += bucketSize) {
      final frameEnd = (frameStart + bucketSize).clamp(0, frameCount);
      var peak = 0.0;
      for (var frameIndex = frameStart; frameIndex < frameEnd; frameIndex++) {
        final sampleOffset = frameIndex * clip.channelCount;
        for (
          var channelIndex = 0;
          channelIndex < clip.channelCount;
          channelIndex++
        ) {
          final amplitude = clip.samples[sampleOffset + channelIndex].abs();
          if (amplitude > peak) {
            peak = amplitude;
          }
        }
      }
      amplitudes.add(peak.clamp(0.0, 1.0));
    }

    return _LinkedAudioWaveformData(
      amplitudes: List<double>.unmodifiable(amplitudes),
      maximumOffsetMilliseconds: maximumOffsetMilliseconds,
    );
  }

  final List<double> amplitudes;
  final int maximumOffsetMilliseconds;
}

class _LinkedAudioWaveformPainter extends CustomPainter {
  static const double waveformBarHeightFactor = 0.42;
  static const double waveformStrokeWidth = 2;
  static const double minimumVisibleBarHeight = 3;
  static const double playbackCursorRatio = 0.5;

  const _LinkedAudioWaveformPainter({
    required this.waveformData,
    required this.currentOffsetMilliseconds,
  });

  final _LinkedAudioWaveformData? waveformData;
  final int currentOffsetMilliseconds;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = AppColors.surfaceElevated;
    final waveformPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.85)
      ..strokeWidth = waveformStrokeWidth
      ..strokeCap = StrokeCap.round;
    final gridPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    final borderRadius = BorderRadius.circular(AppSpacing.md);
    final rect = Offset.zero & size;
    final roundedRect = borderRadius.toRRect(rect);
    canvas.drawRRect(roundedRect, backgroundPaint);

    const gridDivisions = 8;
    for (var division = 1; division < gridDivisions; division++) {
      final dx = size.width * (division / gridDivisions);
      canvas.drawLine(
        Offset(dx, 0),
        Offset(dx, size.height),
        gridPaint,
      );
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    final waveformData = this.waveformData;
    if (waveformData == null || waveformData.amplitudes.isEmpty) {
      return;
    }

    final markerRatio = waveformData.maximumOffsetMilliseconds == 0
        ? 0.0
        : (currentOffsetMilliseconds / waveformData.maximumOffsetMilliseconds)
            .clamp(0.0, 1.0);
    final playbackCursorX = size.width * playbackCursorRatio;
    final visibleDuration = waveformData.maximumOffsetMilliseconds
        .clamp(1, _LinkedAudioWaveformEditor.maximumVisibleDurationMilliseconds);
    final virtualWaveformWidth =
        size.width *
        (waveformData.maximumOffsetMilliseconds / visibleDuration);
    final waveformShiftX =
        playbackCursorX - (virtualWaveformWidth * markerRatio);

    canvas.save();
    canvas.clipRRect(roundedRect);

    final barWidth = virtualWaveformWidth / waveformData.amplitudes.length;
    final centerY = size.height / 2;
    for (var index = 0; index < waveformData.amplitudes.length; index++) {
      final amplitude = waveformData.amplitudes[index];
      final barHeight = amplitude == 0
          ? 0.0
          : (amplitude * (size.height * waveformBarHeightFactor))
              .clamp(minimumVisibleBarHeight, size.height / 2);
      final dx = waveformShiftX + (index * barWidth) + (barWidth / 2);
      canvas.drawLine(
        Offset(dx, centerY - barHeight),
        Offset(dx, centerY + barHeight),
        waveformPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LinkedAudioWaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.currentOffsetMilliseconds != currentOffsetMilliseconds;
  }
}

/// Compact button used in the audio offset stepper row.
///
/// Displays a text label (e.g. "−100", "+10") with primary-colored text
/// and a subtle border. Designed to be placed alongside a narrow
/// [TextFormField] for fine-grained millisecond offset adjustment.
class _OffsetStepButton extends StatelessWidget {
  const _OffsetStepButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        child: Text(
          label,
          style: AppTextTheme.label.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _accentShortLabelFor(AccentLevel accent) {
  switch (accent) {
    case AccentLevel.high:
      return 'H';
    case AccentLevel.normal:
      return 'N';
    case AccentLevel.low:
      return 'L';
    case AccentLevel.mute:
      return 'M';
  }
}
