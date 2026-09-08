import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/audio/i_audio_device_service.dart';
import '../../core/domain/click_sound_set.dart';
import '../../core/providers/app_variant_provider.dart';
import '../../core/providers/audio_mixer_provider.dart';
import '../../core/providers/service_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_animated_background.dart';
import '../../core/widgets/td_button.dart';
import '../../core/widgets/td_dialog.dart';
import '../../core/widgets/td_dropdown_card.dart';
import '../../core/widgets/td_section_header.dart';
import '../../core/widgets/td_slider.dart';
import '../metronome/metronome_screen_controller.dart';
import 'settings_screen_controller.dart';
import 'settings_screen_state.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const double _volumeSliderIconSize = 20;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.showScaffold = true,
  });

  final bool showScaffold;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _soundExpanded = false;
  bool _mixerExpanded = false;
  bool _audioDeviceExpanded = false;
  bool _dataExpanded = false;
  bool _aboutExpanded = false;

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    if (!widget.showScaffold) return content;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TDAnimatedBackground(
        child: SafeArea(child: content),
      ),
    );
  }

  Widget _buildContent() {
    final isDesktop = ref.watch(appVariantProvider).isDesktop;
    final settingsState = ref.watch(settingsScreenControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _buildSoundHeader(),
        if (_soundExpanded) ...[
          const SizedBox(height: AppSpacing.md),
          _buildSoundSection(),
        ],
        const SizedBox(height: AppSpacing.lg),
        _buildMixerHeader(),
        if (_mixerExpanded) ...[
          const SizedBox(height: AppSpacing.md),
          _buildMixerSection(),
        ],
        if (isDesktop) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildAudioDeviceHeader(),
          if (_audioDeviceExpanded) ...[
            const SizedBox(height: AppSpacing.md),
            _buildAudioDeviceSection(),
          ],
        ],
        const SizedBox(height: AppSpacing.lg),
        _buildDataHeader(),
        if (_dataExpanded) ...[
          const SizedBox(height: AppSpacing.md),
          _buildDataSection(settingsState),
        ],
        const SizedBox(height: AppSpacing.lg),
        _buildAboutHeader(),
        if (_aboutExpanded) ...[
          const SizedBox(height: AppSpacing.md),
          const _AboutSection(),
        ],
      ],
    );
  }

  // ── Sound Section ─────────────────────────────────────────────────────────

  Widget _buildSoundHeader() {
    return TDSectionHeader(
      icon: Icons.volume_up,
      label: 'Sound',
      isExpanded: _soundExpanded,
      onToggle: () => setState(() => _soundExpanded = !_soundExpanded),
    );
  }

  Widget _buildSoundSection() {
    final metronomeState = ref.watch(metronomeScreenControllerProvider);
    final metronomeController =
        ref.read(metronomeScreenControllerProvider.notifier);

    return TDDropdownCard<ClickSoundSet>(
      label: 'Click Sound',
      value: metronomeState.clickSoundSet,
      options: ClickSoundSet.values,
      itemLabel: _clickSoundSetLabel,
      onChanged: (value) {
        unawaited(metronomeController.setClickSoundSet(value));
      },
    );
  }

  // ── Mixer Section ─────────────────────────────────────────────────────────

  Widget _buildMixerHeader() {
    return TDSectionHeader(
      icon: Icons.tune,
      label: 'Mixer',
      isExpanded: _mixerExpanded,
      onToggle: () => setState(() => _mixerExpanded = !_mixerExpanded),
    );
  }

  Widget _buildMixerSection() {
    final metronomeState = ref.watch(metronomeScreenControllerProvider);
    final metronomeController =
        ref.read(metronomeScreenControllerProvider.notifier);
    final mixerState = ref.watch(audioMixerControllerProvider);
    final mixerController = ref.read(audioMixerControllerProvider.notifier);

    return Column(
      children: [
        _VolumeSliderRow(
          icon: Icons.volume_up,
          label: 'Master Volume',
          value: metronomeState.masterVolumePercent.toDouble(),
          min: MetronomeScreenController.minimumMasterVolumePercent.toDouble(),
          max: MetronomeScreenController.maximumMasterVolumePercent.toDouble(),
          divisions: MetronomeScreenController.maximumMasterVolumePercent -
              MetronomeScreenController.minimumMasterVolumePercent,
          displayPercent: metronomeState.masterVolumePercent,
          onChanged: (value) {
            metronomeController.setMasterVolumePercent(value.round());
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _VolumeSliderRow(
          icon: Icons.graphic_eq,
          label: 'Metronome',
          value: mixerState.metronomeVolumePercent.toDouble(),
          min: AudioMixerState.minimumVolumePercent.toDouble(),
          max: AudioMixerState.maximumVolumePercent.toDouble(),
          divisions: AudioMixerState.maximumVolumePercent -
              AudioMixerState.minimumVolumePercent,
          displayPercent: mixerState.metronomeVolumePercent,
          onChanged: (value) {
            mixerController.setMetronomeVolumePercent(value.round());
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _VolumeSliderRow(
          icon: Icons.library_music,
          label: 'Song',
          value: mixerState.songVolumePercent.toDouble(),
          min: AudioMixerState.minimumVolumePercent.toDouble(),
          max: AudioMixerState.maximumVolumePercent.toDouble(),
          divisions: AudioMixerState.maximumVolumePercent -
              AudioMixerState.minimumVolumePercent,
          displayPercent: mixerState.songVolumePercent,
          onChanged: (value) {
            mixerController.setSongVolumePercent(value.round());
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _VolumeSliderRow(
          icon: Icons.notifications_active,
          label: 'Cue',
          value: mixerState.cueVolumePercent.toDouble(),
          min: AudioMixerState.minimumVolumePercent.toDouble(),
          max: AudioMixerState.maximumVolumePercent.toDouble(),
          divisions: AudioMixerState.maximumVolumePercent -
              AudioMixerState.minimumVolumePercent,
          displayPercent: mixerState.cueVolumePercent,
          onChanged: (value) {
            mixerController.setCueVolumePercent(value.round());
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _VolumeSliderRow(
          icon: Icons.compare_arrows,
          label: 'Transition',
          value: mixerState.transitionVolumePercent.toDouble(),
          min: AudioMixerState.minimumVolumePercent.toDouble(),
          max: AudioMixerState.maximumVolumePercent.toDouble(),
          divisions: AudioMixerState.maximumVolumePercent -
              AudioMixerState.minimumVolumePercent,
          displayPercent: mixerState.transitionVolumePercent,
          onChanged: (value) {
            mixerController.setTransitionVolumePercent(value.round());
          },
        ),
      ],
    );
  }

  // ── Audio Device Section (Desktop only) ───────────────────────────────────

  Widget _buildAudioDeviceHeader() {
    return TDSectionHeader(
      icon: Icons.headphones,
      label: 'Audio Device',
      isExpanded: _audioDeviceExpanded,
      onToggle: () => setState(
        () => _audioDeviceExpanded = !_audioDeviceExpanded,
      ),
    );
  }

  Widget _buildAudioDeviceSection() {
    return _AudioDeviceSection(
      audioDeviceService: ref.read(audioDeviceServiceProvider),
    );
  }

  // ── Data Section ──────────────────────────────────────────────────────────

  Widget _buildDataHeader() {
    return TDSectionHeader(
      icon: Icons.folder_outlined,
      label: 'Data',
      isExpanded: _dataExpanded,
      onToggle: () => setState(() => _dataExpanded = !_dataExpanded),
    );
  }

  Future<bool> _showImportConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: tdDialogShape,
        title: const Text('Import Backup', style: AppTextTheme.heading3),
        content: const Text(
          'This will replace all your songs, setlists, and presets '
          'with the data from the backup file. This cannot be undone.',
          style: AppTextTheme.body,
        ),
        actions: [
          TDButton(
            label: 'Cancel',
            variant: TDButtonVariant.secondary,
            onPressed: () => Navigator.pop(context, false),
          ),
          TDButton(
            label: 'Replace All Data',
            variant: TDButtonVariant.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Widget _buildDataSection(SettingsScreenState settingsState) {
    final controller = ref.read(settingsScreenControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (settingsState.errorMessage != null) ...[
          Text(
            settingsState.errorMessage!,
            style: AppTextTheme.bodySecondary.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (settingsState.successMessage != null) ...[
          Text(
            settingsState.successMessage!,
            style:
                AppTextTheme.bodySecondary.copyWith(color: AppColors.success),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const Text(
          'Backups contain songs, setlists, and settings. '
          'Audio files are not included and must be re-linked after import.',
          style: AppTextTheme.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.md),
        TDButton(
          label: 'Export Backup',
          icon: Icons.upload_outlined,
          variant: TDButtonVariant.secondary,
          isLoading: settingsState.isExporting,
          onPressed:
              settingsState.isExporting ? null : () => controller.exportBackup(),
        ),
        const SizedBox(height: AppSpacing.md),
        TDButton(
          label: 'Import Backup',
          icon: Icons.download_outlined,
          variant: TDButtonVariant.secondary,
          isLoading: settingsState.isImporting,
          onPressed: settingsState.isImporting
              ? null
              : () => controller.importBackup(
                    confirm: () => _showImportConfirmation(context),
                  ),
        ),
      ],
    );
  }

  // ── About Section ─────────────────────────────────────────────────────────

  Widget _buildAboutHeader() {
    return TDSectionHeader(
      icon: Icons.info_outline,
      label: 'About',
      isExpanded: _aboutExpanded,
      onToggle: () => setState(() => _aboutExpanded = !_aboutExpanded),
    );
  }
}

// ─── Audio Device Section ────────────────────────────────────────────────────

class _AudioDeviceSection extends StatefulWidget {
  const _AudioDeviceSection({required this.audioDeviceService});

  final IAudioDeviceService audioDeviceService;

  @override
  State<_AudioDeviceSection> createState() => _AudioDeviceSectionState();
}

class _AudioDeviceSectionState extends State<_AudioDeviceSection> {
  /// Sentinel value distinguishing "user chose System Default" from
  /// "no selection made yet".
  static const _systemDefaultSentinel = 'system-default';

  List<AudioOutputDevice> _devices = const [];

  /// Tracks the user's explicit choice. Uses [_systemDefaultSentinel] for
  /// System Default so we can distinguish it from "never selected".
  String _selectedKey = _systemDefaultSentinel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final persisted = widget.audioDeviceService.selectedDeviceId;
    _selectedKey = persisted ?? _systemDefaultSentinel;
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final devices = await widget.audioDeviceService.listDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _isLoading = false;
    });
  }

  Future<void> _selectDevice(AudioOutputDevice device) async {
    final activeId = await widget.audioDeviceService.selectDevice(device.id);
    if (!mounted) return;
    setState(() => _selectedKey = activeId ?? _systemDefaultSentinel);
  }

  String? _deviceIdForKey(String key) =>
      key == _systemDefaultSentinel ? null : key;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final selectedDevice = _devices.firstWhere(
      (device) => device.id == _deviceIdForKey(_selectedKey),
      orElse: () => _devices.first,
    );

    return Row(
      children: [
        Expanded(
          child: TDDropdownCard<AudioOutputDevice>(
            label: 'Output Device',
            value: selectedDevice,
            options: _devices,
            itemLabel: (device) => device.name,
            onChanged: _selectDevice,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          icon: const Icon(
            Icons.refresh,
            color: AppColors.textSecondary,
          ),
          onPressed: _loadDevices,
          tooltip: 'Refresh devices',
        ),
      ],
    );
  }
}

// ─── About Section ───────────────────────────────────────────────────────────

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  static const _logoSize = 48.0;
  static const _logoAsset = 'assets/images/splash_logo_1x.png';

  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = '${info.version} (${info.buildNumber})';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          _logoAsset,
          width: _logoSize,
          height: _logoSize,
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TempoDeck', style: AppTextTheme.heading2),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _version.isEmpty ? 'Loading...' : 'Version $_version',
              style: AppTextTheme.bodySecondary,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Volume Slider Row ──────────────────────────────────────────────────────

class _VolumeSliderRow extends StatelessWidget {
  const _VolumeSliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayPercent,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final int displayPercent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: _volumeSliderIconSize),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, style: AppTextTheme.heading3),
            ),
            Text('$displayPercent%', style: AppTextTheme.numeric),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TDSlider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _clickSoundSetLabel(ClickSoundSet clickSoundSet) {
  return switch (clickSoundSet) {
    ClickSoundSet.tock => 'Tock',
    ClickSoundSet.blip => 'Blip',
    ClickSoundSet.drumKit => 'Drum Kit',
    ClickSoundSet.hype => 'Hype',
    ClickSoundSet.metalKit => 'Metal Kit',
    ClickSoundSet.mightyKit => 'Mighty Kit',
  };
}
