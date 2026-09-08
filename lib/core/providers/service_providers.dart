import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../audio/asset_click_sound_clip_loader.dart';
import '../audio/i_audio_device_service.dart';
import '../audio/soloud_audio_device_service.dart';
import '../audio/stub_audio_device_service.dart';
import '../backup/json_backup_exporter.dart';
import '../backup/json_backup_restorer.dart';
import '../audio/click_track_export_augmenter.dart';
import '../audio/core_export_engine_factory.dart';
import '../audio/tap_tempo_detector.dart';
import '../audio/export_project_source_resolver.dart';
import '../audio/ffmpeg_audio_export_transcoder.dart';
import '../audio/ffmpeg_linked_audio_clip_loader.dart';
import '../audio/process_ffmpeg_audio_export_client.dart';
import '../audio/audio_playback_session.dart';
import '../audio/foreground_playback_service.dart';
import '../audio/i_audio_engine.dart';
import '../audio/i_export_engine.dart';
import '../audio/linked_audio_export_augmenter.dart';
import '../audio/soloud_audio_engine.dart';
import '../audio/soloud_client.dart';
import '../audio/soloud_linked_audio_clip_loader.dart';
import '../files/export_file_service.dart';
import '../files/linked_audio_file_storage.dart';
import '../files/linked_audio_import_service.dart';
import '../files/linked_audio_path_repair_service.dart';
import '../files/linked_audio_picker.dart';
import '../../features/live/live_playback_plan_loader.dart';
import '../../features/metronome/metronome_screen_controller.dart';
import 'app_variant_provider.dart';
import 'audio_mixer_provider.dart';
import 'repository_providers.dart';

final audioPlaybackSessionProvider = Provider<AudioPlaybackSession>(
  (ref) => SystemAudioPlaybackSession(),
);

final soLoudClientProvider = Provider<SoLoudClient>(
  (ref) => FlutterSoLoudClient(),
);

final audioEngineProvider = Provider<IAudioEngine>(
  (ref) => SoLoudAudioEngine(
    soLoudClient: ref.read(soLoudClientProvider),
    playbackSession: ref.read(audioPlaybackSessionProvider),
  ),
);

final foregroundPlaybackServiceProvider =
    Provider<ForegroundPlaybackService>(
  (ref) => PlatformForegroundPlaybackService(),
);

/// Incremented when playback is stopped externally (audio interruption,
/// app backgrounded). Controllers watch this to sync their UI state.
final externalAudioStopCounterProvider = StateProvider<int>((ref) => 0);

/// Initializes the audio engine, loads persisted mixer and metronome settings,
/// and exposes the result as [AsyncValue].
///
/// Watch this provider from the root widget to trigger initialization eagerly.
/// If initialization fails the error is logged and the provider transitions to
/// [AsyncError] so any part of the UI can react to the degraded state.
final audioInitProvider = FutureProvider<void>((ref) async {
  try {
    await ref.read(audioEngineProvider).initialize();
    await ref
        .read(audioMixerControllerProvider.notifier)
        .loadPersistedSettings();
    await ref
        .read(metronomeScreenControllerProvider.notifier)
        .loadPersistedSettings();
  } catch (error, stackTrace) {
    Logger('AudioInit').severe(
      'Audio engine initialization failed.',
      error,
      stackTrace,
    );
    rethrow;
  }
});

final songExportSourceLoaderProvider = Provider<SongExportSourceLoader>(
  (ref) => ref.watch(songRepositoryProvider),
);

final setlistExportSourceLoaderProvider = Provider<SetlistExportSourceLoader>(
  (ref) => ref.watch(setlistRepositoryProvider),
);

final linkedAudioClipLoaderProvider = Provider<LinkedAudioClipLoader>(
  (ref) => switch (ref.watch(appVariantProvider)) {
    AppVariant.mobile => FfmpegLinkedAudioClipLoader(
      ffmpegAudioExportClient: ref.watch(ffmpegAudioExportClientProvider),
    ),
    AppVariant.desktop => SoLoudLinkedAudioClipLoader(
      soLoudClient: ref.read(soLoudClientProvider),
    ),
  },
);

final ffmpegAudioExportClientProvider = Provider<FfmpegAudioExportClient>(
  (ref) => switch (ref.watch(appVariantProvider)) {
    AppVariant.mobile => const FfmpegKitAudioExportClient(),
    AppVariant.desktop => const ProcessFfmpegAudioExportClient(),
  },
);

final clickSoundClipLoaderProvider = Provider<ClickSoundClipLoader>(
  (ref) => const AssetClickSoundClipLoader(),
);

final exportEngineProvider = Provider<IExportEngine>(
  (ref) => const CoreExportEngineFactory().create(
    songLoader: ref.watch(songExportSourceLoaderProvider),
    setlistLoader: ref.watch(setlistExportSourceLoaderProvider),
    linkedAudioClipLoader: ref.watch(linkedAudioClipLoaderProvider),
    clickSoundClipLoader: ref.watch(clickSoundClipLoaderProvider),
    ffmpegAudioExportClient: ref.watch(ffmpegAudioExportClientProvider),
    linkedAudioPathRepairService:
        ref.watch(linkedAudioPathRepairServiceProvider),
  ),
);

final linkedAudioPickerProvider = Provider<LinkedAudioPicker>(
  (ref) => const FilePickerLinkedAudioPicker(),
);

final linkedAudioFileStorageProvider = Provider<LinkedAudioFileStorage>(
  (ref) => AppLinkedAudioFileStorage(),
);

final linkedAudioImportServiceProvider = Provider<LinkedAudioImportService>(
  // All platforms copy audio files into app-owned storage.
  // macOS requires this because the sandbox revokes file access after restart.
  // Windows doesn't need it, but copying ensures consistent behavior and
  // safe cleanup on all platforms.
  (ref) => CopyingLinkedAudioImportService(
    fileStorage: ref.watch(linkedAudioFileStorageProvider),
  ),
);

final linkedAudioPathRepairServiceProvider = Provider<LinkedAudioPathRepairService>(
  (ref) => AppLinkedAudioPathRepairService(),
);

final tapTempoDetectorProvider = Provider<TapTempoDetector>(
  (ref) => TapTempoDetector(),
);

final livePlaybackPlanLoaderProvider = Provider<LivePlaybackPlanLoader>(
  (ref) => LivePlaybackPlanLoader(
    songRepository: ref.watch(songRepositoryProvider),
  ),
);

final exportFileServiceProvider = Provider<ExportFileService>(
  (ref) => switch (ref.watch(appVariantProvider)) {
    AppVariant.mobile => Platform.isAndroid
        ? const AndroidExportFileService()
        : const IosExportFileService(),
    AppVariant.desktop => const DesktopExportFileService(),
  },
);

final backupExporterProvider = Provider<JsonBackupExporter>(
  (ref) => JsonBackupExporter(
    songRepository: ref.watch(songRepositoryProvider),
    setlistRepository: ref.watch(setlistRepositoryProvider),
    presetRepository: ref.watch(presetRepositoryProvider),
  ),
);

final backupRestorerProvider = Provider<JsonBackupRestorer>(
  (ref) => JsonBackupRestorer(
    songRepository: ref.watch(songRepositoryProvider),
    setlistRepository: ref.watch(setlistRepositoryProvider),
    presetRepository: ref.watch(presetRepositoryProvider),
    runInTransaction: (action) =>
        ref.watch(appDatabaseProvider).transaction(action),
  ),
);

final audioDeviceServiceProvider = Provider<IAudioDeviceService>(
  (ref) => switch (ref.watch(appVariantProvider)) {
    AppVariant.mobile => StubAudioDeviceService(),
    AppVariant.desktop => SoLoudAudioDeviceService(
      soLoudClient: ref.read(soLoudClientProvider),
      audioEngine: ref.read(audioEngineProvider),
    ),
  },
);
