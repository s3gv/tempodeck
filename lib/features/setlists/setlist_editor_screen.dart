import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:logging/logging.dart';

import '../../core/audio/i_audio_engine.dart';
import '../../core/audio/i_export_engine.dart';
import '../../core/audio/text_to_speech_client.dart';
import '../../core/domain/audio_cue.dart';
import '../../core/domain/setlist.dart';
import '../../core/files/linked_audio_file_storage.dart';
import '../../core/files/linked_audio_import_service.dart';
import '../../core/files/linked_audio_picker.dart';
import '../../core/providers/app_variant_provider.dart';
import '../../core/providers/audio_mixer_provider.dart';
import '../../core/providers/service_providers.dart';
import '../../core/validation/setlist_write_validator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_animated_background.dart';
import '../../core/widgets/td_button.dart';
import '../../core/widgets/td_dialog.dart';
import '../../core/widgets/td_live_access_bar.dart';
import '../../core/widgets/td_toggle.dart';
import '../export/export_sheet.dart';
import '../live/live_view_context.dart';
import 'setlist_details_provider.dart';
import 'setlists_screen_controller.dart';

class SetlistEditorScreen extends ConsumerWidget {
  static const _transitionStepSectionSpacing = SizedBox(height: AppSpacing.md);

  const SetlistEditorScreen({
    super.key,
    required this.setlistId,
    this.showScaffold = true,
  });

  final String setlistId;
  final bool showScaffold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlistAsync = ref.watch(setlistDetailsProvider(setlistId));
    final isMobile = !ref.watch(appVariantProvider).isDesktop;

    final content = setlistAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (setlist) {
        if (setlist == null) {
          return const Center(child: Text('Setlist not found'));
        }

        // On desktop the play button in the navigation rail reads the
        // activeEditorSetlistProvider to know which setlist to launch.
        Future.microtask(() {
          ref.read(activeEditorSetlistProvider.notifier).state = setlist;
        });

        final list = _SetlistItemsView(
          setlist: setlist,
          addBottomPadding: isMobile,
        );

        if (!isMobile) return list;

        return Stack(
          children: [
            list,
            TDLiveAccessBar(
              onPlay: () async {
                ref
                    .read(liveViewContextProvider.notifier)
                    .set(SetlistViewContext(setlist: setlist));
                context.go('/setlists/${setlist.id}/live');
              },
            ),
          ],
        );
      },
    );

    if (!showScaffold) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(setlistAsync.valueOrNull?.title ?? 'Setlist'),
        backgroundColor: Colors.transparent,
        actions: [
          if (setlistAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export',
              onPressed: () {
                final setlist = setlistAsync.valueOrNull!;
                showExportSheet(
                  context: context,
                  source: SetlistExportSource(setlist.id),
                  title: setlist.title,
                );
              },
            ),
        ],
      ),
      body: TDAnimatedBackground(child: content),
    );
  }
}

class _SetlistItemsView extends ConsumerWidget {
  const _SetlistItemsView({
    required this.setlist,
    this.addBottomPadding = false,
  });

  final Setlist setlist;
  final bool addBottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setlistsScreenControllerProvider);

    if (setlist.items.isEmpty) {
      return const Center(child: Text('No songs in this setlist yet'));
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, addBottomPadding ? 100 : AppSpacing.md),
      itemCount: setlist.items.length,
      separatorBuilder: (_, __) => const Divider(color: AppColors.border),
      itemBuilder: (context, index) {
        final item = setlist.items[index];
        final isFirst = index == 0;
        final isLast = index == setlist.items.length - 1;
        return Column(
          key: Key('setlistEditorItem-${item.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.songTitle, style: AppTextTheme.body),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Position ${index + 1}', style: AppTextTheme.bodySecondary),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: isFirst
                        ? null
                        : () => controller.moveSetlistItem(
                              setlist,
                              oldIndex: index,
                              newIndex: index - 1,
                            ),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: isLast
                        ? null
                        : () => controller.moveSetlistItem(
                              setlist,
                              oldIndex: index,
                              newIndex: index + 1,
                            ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Expanded(child: Text('Playback enabled', style: AppTextTheme.body)),
                  TDToggle(
                    value: item.playbackEnabled,
                    onChanged: (value) {
                      controller.updateSetlistItemPlaybackFlags(
                        setlist,
                        itemId: item.id,
                        playbackEnabled: value,
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Expanded(child: Text('Play attached audio', style: AppTextTheme.body)),
                  TDToggle(
                    value: item.playAttachedAudio,
                    onChanged: (value) {
                      controller.updateSetlistItemPlaybackFlags(
                        setlist,
                        itemId: item.id,
                        playAttachedAudio: value,
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
              child: _TransitionStepsSection(
                setlist: setlist,
                item: item,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransitionStepsSection extends ConsumerWidget {
  static final _logger = Logger('_TransitionStepsSection');
  const _TransitionStepsSection({
    required this.setlist,
    required this.item,
  });

  final Setlist setlist;
  final SetlistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setlistsScreenControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Transition steps',
                style: AppTextTheme.heading3,
              ),
            ),
            TDButton(
              label: 'Add',
              icon: Icons.add,
              variant: TDButtonVariant.secondary,
              onPressed: () => _promptAddTransitionStep(
                context,
                controller: controller,
                audioEngine: ref.read(audioEngineProvider),
                linkedAudioPicker: ref.read(linkedAudioPickerProvider),
                linkedAudioImportService: ref.read(linkedAudioImportServiceProvider),
                linkedAudioFileStorage: ref.read(linkedAudioFileStorageProvider),
                cueVolumeFactor: ref.read(audioMixerControllerProvider.notifier).cueVolumeFactor(),
              ),
            ),
          ],
        ),
        if (item.transitionSteps.isEmpty)
          const Text('No transition steps configured')
        else
          for (var index = 0; index < item.transitionSteps.length; index++) ...[
            if (index > 0) SetlistEditorScreen._transitionStepSectionSpacing,
            _TransitionStepTile(
              setlist: setlist,
              item: item,
              step: item.transitionSteps[index],
              stepIndex: index,
              stepCount: item.transitionSteps.length,
            ),
          ],
      ],
    );
  }

  Future<void> _promptAddTransitionStep(
    BuildContext context, {
    required SetlistsScreenController controller,
    required IAudioEngine audioEngine,
    required LinkedAudioPicker linkedAudioPicker,
    required LinkedAudioImportService linkedAudioImportService,
    required LinkedAudioFileStorage linkedAudioFileStorage,
    required double cueVolumeFactor,
  }) async {
    final pendingDeletions = <String>[];
    final newStep = await showDialog<SetlistTransitionStep>(
      context: context,
      builder: (context) => _TransitionStepDialog(
        title: 'Add transition step',
        audioEngine: audioEngine,
        linkedAudioPicker: linkedAudioPicker,
        linkedAudioImportService: linkedAudioImportService,
        linkedAudioFileStorage: linkedAudioFileStorage,
        cueVolumeFactor: cueVolumeFactor,
        onReplacedFilePath: pendingDeletions.add,
        createStep: controller.createTransitionStep,
        initialStep: null,
      ),
    );
    if (newStep == null || !context.mounted) {
      return;
    }

    await controller.addTransitionStep(
      setlist,
      itemId: item.id,
      step: newStep,
    );

    for (final path in pendingDeletions) {
      unawaited(
        linkedAudioFileStorage.deleteFromStorage(path).catchError(
          (Object error) {
            _logger.warning('Failed to delete replaced custom file.', error);
          },
        ),
      );
    }
  }
}

class _TransitionStepTile extends ConsumerWidget {
  const _TransitionStepTile({
    required this.setlist,
    required this.item,
    required this.step,
    required this.stepIndex,
    required this.stepCount,
  });

  static final _logger = Logger('_TransitionStepTile');

  final Setlist setlist;
  final SetlistItem item;
  final SetlistTransitionStep step;
  final int stepIndex;
  final int stepCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setlistsScreenControllerProvider);

    return ListTile(
      title: Text(_stepTitle(step)),
      subtitle: Text(_stepSubtitle(step)),
      trailing: Wrap(
        spacing: AppSpacing.xs,
        children: [
          IconButton(
            tooltip: 'Move step up',
            onPressed: stepIndex == 0
                ? null
                : () => controller.reorderTransitionStep(
                      setlist,
                      itemId: item.id,
                      oldIndex: stepIndex,
                      newIndex: stepIndex - 1,
                    ),
            icon: Icon(
              Icons.keyboard_arrow_up,
              color: stepIndex == 0 ? null : AppColors.primary,
            ),
          ),
          IconButton(
            tooltip: 'Move step down',
            onPressed: stepIndex == stepCount - 1
                ? null
                : () => controller.reorderTransitionStep(
                      setlist,
                      itemId: item.id,
                      oldIndex: stepIndex,
                      newIndex: stepIndex + 1,
                    ),
            icon: Icon(
              Icons.keyboard_arrow_down,
              color:
                  stepIndex == stepCount - 1 ? null : AppColors.primary,
            ),
          ),
          IconButton(
            tooltip: 'Edit step',
            onPressed: () => _promptEditTransitionStep(
              context,
              controller: controller,
              audioEngine: ref.read(audioEngineProvider),
              linkedAudioPicker: ref.read(linkedAudioPickerProvider),
              linkedAudioImportService: ref.read(linkedAudioImportServiceProvider),
              linkedAudioFileStorage: ref.read(linkedAudioFileStorageProvider),
              cueVolumeFactor: ref.read(audioMixerControllerProvider.notifier).cueVolumeFactor(),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete step',
            onPressed: () => controller.removeTransitionStep(
              setlist,
              itemId: item.id,
              stepId: step.id,
            ),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Future<void> _promptEditTransitionStep(
    BuildContext context, {
    required SetlistsScreenController controller,
    required IAudioEngine audioEngine,
    required LinkedAudioPicker linkedAudioPicker,
    required LinkedAudioImportService linkedAudioImportService,
    required LinkedAudioFileStorage linkedAudioFileStorage,
    required double cueVolumeFactor,
  }) async {
    final pendingDeletions = <String>[];
    final updatedStep = await showDialog<SetlistTransitionStep>(
      context: context,
      builder: (context) => _TransitionStepDialog.edit(
        title: 'Edit transition step',
        audioEngine: audioEngine,
        cueVolumeFactor: cueVolumeFactor,
        linkedAudioPicker: linkedAudioPicker,
        linkedAudioImportService: linkedAudioImportService,
        linkedAudioFileStorage: linkedAudioFileStorage,
        onReplacedFilePath: pendingDeletions.add,
        step: step,
      ),
    );
    if (updatedStep == null || !context.mounted) {
      return;
    }

    await controller.updateTransitionStep(
      setlist,
      itemId: item.id,
      step: updatedStep,
    );

    // Clean up replaced files only after the setlist update is persisted.
    for (final path in pendingDeletions) {
      unawaited(
        linkedAudioFileStorage.deleteFromStorage(path).catchError(
          (Object error) {
            _logger.warning('Failed to delete replaced custom file.', error);
          },
        ),
      );
    }
  }
}

class _TransitionStepDialog extends StatefulWidget {
  const _TransitionStepDialog({
    required this.title,
    required this.audioEngine,
    required this.linkedAudioPicker,
    required this.linkedAudioImportService,
    required this.linkedAudioFileStorage,
    required this.cueVolumeFactor,
    this.onReplacedFilePath,
    this.createStep,
    required this.initialStep,
  });

  const _TransitionStepDialog.edit({
    required this.title,
    required this.audioEngine,
    required this.linkedAudioPicker,
    required this.linkedAudioImportService,
    required this.linkedAudioFileStorage,
    required this.cueVolumeFactor,
    this.onReplacedFilePath,
    required SetlistTransitionStep step,
  })  : createStep = null,
        initialStep = step;

  final String title;
  final IAudioEngine audioEngine;
  final LinkedAudioPicker linkedAudioPicker;
  final LinkedAudioImportService linkedAudioImportService;
  final LinkedAudioFileStorage linkedAudioFileStorage;
  final double cueVolumeFactor;
  final ValueChanged<String>? onReplacedFilePath;
  final SetlistTransitionStep? initialStep;
  final SetlistTransitionStep Function({
    required SetlistTransitionStepType type,
    required int value,
    AudioCue? audioCue,
  })? createStep;

  @override
  State<_TransitionStepDialog> createState() => _TransitionStepDialogState();
}

class _TransitionStepDialogState extends State<_TransitionStepDialog> {
  static final _logger = Logger('_TransitionStepDialog');

  static const _audioCueTypes = [
    AudioCueType.intervalSignal,
    AudioCueType.maxSignal,
    AudioCueType.lowPulse,
    AudioCueType.midPulse,
    AudioCueType.highPulse,
    AudioCueType.voice,
    AudioCueType.customFile,
  ];

  final _formKey = GlobalKey<FormState>();
  late SetlistTransitionStepType _type;
  late AudioCueType _audioCueType;
  late final TextEditingController _valueController;
  late final TextEditingController _pauseMinutesController;
  late final TextEditingController _pauseSecondsController;
  late final TextEditingController _voiceTextController;
  late final TextEditingController _customFilePathController;
  late final TextEditingController _customFileDisplayNameController;
  String? _selectedVoiceIdentifier;
  bool _isPreviewingVoice = false;
  bool _isPreviewingCustomFile = false;
  final List<String> _replacedCustomFilePaths = [];
  bool _isLoadingVoices = true;
  List<TextToSpeechVoice> _availableVoices = [];
  String? _voiceLoadError;

  @override
  void initState() {
    super.initState();
    final initialStep = widget.initialStep;
    _type = initialStep?.type ?? SetlistTransitionStepType.countInBars;
    _audioCueType = initialStep?.audioCue?.type ?? AudioCueType.highPulse;
    _valueController = TextEditingController(
      text: _initialValueText(initialStep),
    );
    final initialPauseSeconds = initialStep?.type == SetlistTransitionStepType.pauseTimer
        ? initialStep!.value
        : 0;
    _pauseMinutesController = TextEditingController(
      text: '${initialPauseSeconds ~/ 60}',
    );
    _pauseSecondsController = TextEditingController(
      text: '${initialPauseSeconds % 60}',
    );
    _voiceTextController = TextEditingController(
      text: initialStep?.audioCue?.voiceText ?? '',
    );
    _selectedVoiceIdentifier = initialStep?.audioCue?.voiceIdentifier;
    _customFilePathController = TextEditingController(
      text: initialStep?.audioCue?.customFilePath ?? '',
    );
    _customFileDisplayNameController = TextEditingController(
      text: initialStep?.audioCue?.customFileDisplayName ?? '',
    );
    _loadAvailableVoices();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _pauseMinutesController.dispose();
    _pauseSecondsController.dispose();
    _voiceTextController.dispose();
    _customFilePathController.dispose();
    _customFileDisplayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableVoices() async {
    try {
      final voices = await widget.audioEngine.getAvailableVoices();
      if (!mounted) return;
      final knownIdentifiers =
          voices.map((v) => v.identifier).whereType<String>().toSet();
      setState(() {
        _isLoadingVoices = false;
        _availableVoices = voices;
        _voiceLoadError = voices.isEmpty
            ? 'No voices available. Install a TTS engine on this device.'
            : null;
        // Reset to default if the saved voice is no longer available.
        if (_selectedVoiceIdentifier != null &&
            !knownIdentifiers.contains(_selectedVoiceIdentifier)) {
          _selectedVoiceIdentifier = null;
        }
      });
    } catch (error, stackTrace) {
      _logger.warning('Failed to load available voices.', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoadingVoices = false;
        _voiceLoadError = 'Voice cues are not available on this device.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<SetlistTransitionStepType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Step type'),
                items: SetlistTransitionStepType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_stepTypeLabel(type)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _type = value;
                    if (_type == SetlistTransitionStepType.manual ||
                        _type == SetlistTransitionStepType.audio) {
                      _valueController.text = '0';
                    }
                  });
                },
              ),
              if (_type == SetlistTransitionStepType.countInBars)
                TextFormField(
                  controller: _valueController,
                  decoration: const InputDecoration(
                    labelText: 'Count-in bars',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _validateValue,
                ),
              if (_type == SetlistTransitionStepType.pauseTimer)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _pauseMinutesController,
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _validatePauseMinutes,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _pauseSecondsController,
                        decoration: const InputDecoration(
                          labelText: 'Seconds',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _validatePauseSeconds,
                      ),
                    ),
                  ],
                ),
              if (_type == SetlistTransitionStepType.audio) ...[
                DropdownButtonFormField<AudioCueType>(
                  initialValue: _audioCueType,
                  decoration: const InputDecoration(labelText: 'Audio cue'),
                  items: _audioCueTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_audioCueTypeLabel(type)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _audioCueType = value;
                    });
                  },
                ),
                if (_audioCueType == AudioCueType.voice) ...[
                  TextFormField(
                    controller: _voiceTextController,
                    decoration: const InputDecoration(labelText: 'Voice text'),
                    validator: _validateVoiceText,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_isLoadingVoices)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_voiceLoadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        _voiceLoadError!,
                        style: AppTextTheme.bodySecondary.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    )
                  else if (_availableVoices.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedVoiceIdentifier,
                      decoration: const InputDecoration(labelText: 'Voice'),
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
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPreviewingVoice
                              ? Icons.stop
                              : Icons.play_arrow,
                        ),
                        onPressed: _voiceTextController.text.trim().isEmpty ||
                                _voiceLoadError != null
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
                    children: [
                      Expanded(
                        child: Text(
                          _customFileDisplayNameController.text.isNotEmpty
                              ? _customFileDisplayNameController.text
                              : 'No file selected',
                          style: TextStyle(
                            color: _customFileDisplayNameController
                                    .text.isNotEmpty
                                ? null
                                : AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      TDButton(
                        label: 'Pick file',
                        icon: Icons.folder_open,
                        variant: TDButtonVariant.secondary,
                        onPressed: _pickCustomFile,
                      ),
                    ],
                  ),
                  if (_customFilePathController.text.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'A custom audio file is required',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (_customFilePathController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        IconButton(
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _initialValueText(SetlistTransitionStep? initialStep) {
    if (initialStep == null) {
      return '${SetlistWriteValidator.minimumCountInBars}';
    }
    return '${initialStep.value}';
  }

  String? _validateValue(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) {
      return 'Enter a whole number';
    }
    if (_type == SetlistTransitionStepType.countInBars &&
        parsed < SetlistWriteValidator.minimumCountInBars) {
      return 'Must be at least ${SetlistWriteValidator.minimumCountInBars}';
    }
    if (_type == SetlistTransitionStepType.pauseTimer &&
        parsed < SetlistWriteValidator.minimumPauseSeconds) {
      return 'Must not be negative';
    }
    return null;
  }

  String? _validatePauseMinutes(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return 'Enter 0 or more';
    }
    return null;
  }

  String? _validatePauseSeconds(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0 || parsed > 59) {
      return '0–59';
    }
    final minutes = int.tryParse(_pauseMinutesController.text.trim()) ?? 0;
    if (minutes == 0 && parsed == 0) {
      return 'Must be > 0';
    }
    return null;
  }

  String? _validateVoiceText(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'Voice text is required';
    }
    return null;
  }


  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_type == SetlistTransitionStepType.audio &&
        _audioCueType == AudioCueType.customFile &&
        _customFilePathController.text.trim().isEmpty) {
      return;
    }

    final int value;
    switch (_type) {
      case SetlistTransitionStepType.countInBars:
        value = int.parse(_valueController.text.trim());
      case SetlistTransitionStepType.pauseTimer:
        final minutes = int.parse(_pauseMinutesController.text.trim());
        final seconds = int.parse(_pauseSecondsController.text.trim());
        value = minutes * 60 + seconds;
      case SetlistTransitionStepType.manual:
      case SetlistTransitionStepType.audio:
        value = 0;
    }
    final audioCue = _type == SetlistTransitionStepType.audio
        ? AudioCue(
            type: _audioCueType,
            volumePercent:
                widget.initialStep?.audioCue?.volumePercent ?? 100,
            voiceText: _audioCueType == AudioCueType.voice
                ? _voiceTextController.text.trim()
                : null,
            voiceIdentifier: _audioCueType == AudioCueType.voice
                ? _selectedVoiceIdentifier
                : null,
            customFilePath: _audioCueType == AudioCueType.customFile
                ? _customFilePathController.text.trim()
                : null,
            customFileDisplayName: _audioCueType == AudioCueType.customFile
                ? _optionalTrimmed(_customFileDisplayNameController.text)
                : null,
          )
        : null;

    final step = widget.initialStep == null
        ? widget.createStep!(
            type: _type,
            value: value,
            audioCue: audioCue,
          )
        : SetlistTransitionStep(
            id: widget.initialStep!.id,
            type: _type,
            value: value,
            audioCue: audioCue,
          );

    // Pass replaced file paths to the parent for deferred cleanup after
    // the setlist update is durably saved.
    for (final path in _replacedCustomFilePaths) {
      widget.onReplacedFilePath?.call(path);
    }
    _replacedCustomFilePaths.clear();
    Navigator.of(context).pop(step);
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
        volume: widget.cueVolumeFactor,
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

  Future<void> _pickCustomFile() async {
    final pickedFile =
        await widget.linkedAudioPicker.pickAudioFile();
    if (pickedFile == null || !mounted) {
      return;
    }

    final importedFile = await widget.linkedAudioImportService
        .importPickedAudioFile(pickedFile);

    final oldPath = _customFilePathController.text.trim();
    if (oldPath.isNotEmpty) {
      _replacedCustomFilePaths.add(oldPath);
    }

    setState(() {
      _customFilePathController.text = importedFile.filePath;
      _customFileDisplayNameController.text = importedFile.displayName;
    });
  }

  String? _optionalTrimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

String _stepTitle(SetlistTransitionStep step) {
  return switch (step.type) {
    SetlistTransitionStepType.countInBars => 'Count-in bars',
    SetlistTransitionStepType.pauseTimer => 'Pause timer',
    SetlistTransitionStepType.manual => 'Manual wait',
    SetlistTransitionStepType.audio => 'Audio cue',
  };
}

String _stepSubtitle(SetlistTransitionStep step) {
  return switch (step.type) {
    SetlistTransitionStepType.countInBars => '${step.value} bars',
    SetlistTransitionStepType.pauseTimer => _formatPauseTimer(step.value),
    SetlistTransitionStepType.manual => 'Wait for manual continue',
    SetlistTransitionStepType.audio => _audioCueSummary(step.audioCue),
  };
}

String _stepTypeLabel(SetlistTransitionStepType type) {
  return switch (type) {
    SetlistTransitionStepType.countInBars => 'Count-in bars',
    SetlistTransitionStepType.pauseTimer => 'Pause timer',
    SetlistTransitionStepType.manual => 'Manual wait',
    SetlistTransitionStepType.audio => 'Audio cue',
  };
}

String _formatPauseTimer(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _audioCueTypeLabel(AudioCueType type) {
  return switch (type) {
    AudioCueType.intervalSignal => 'Interval signal',
    AudioCueType.maxSignal => 'Max signal',
    AudioCueType.lowPulse => 'Low pulse',
    AudioCueType.midPulse => 'Mid pulse',
    AudioCueType.highPulse => 'High pulse',
    AudioCueType.voice => 'Voice',
    AudioCueType.customFile => 'Custom file',
  };
}

String _audioCueSummary(AudioCue? audioCue) {
  if (audioCue == null) {
    return 'No audio cue';
  }
  return switch (audioCue.type) {
    AudioCueType.voice =>
      'Voice: ${audioCue.voiceText ?? ''}',
    AudioCueType.customFile =>
      'Custom file: ${audioCue.customFileDisplayName ?? audioCue.customFilePath ?? ''}',
    _ =>
      _audioCueTypeLabel(audioCue.type),
  };
}
