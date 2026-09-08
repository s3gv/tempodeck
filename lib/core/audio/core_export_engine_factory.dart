import '../files/linked_audio_path_repair_service.dart';
import 'audio_cue_export_augmenter.dart';
import 'click_track_export_augmenter.dart';
import 'export_engine.dart';
import 'export_project_source_resolver.dart';
import 'ffmpeg_audio_export_transcoder.dart';
import 'linked_audio_export_augmenter.dart';
import 'offline_pcm_audio_renderer.dart';

class CoreExportEngineFactory {
  const CoreExportEngineFactory();

  ExportEngine create({
    required SongExportSourceLoader songLoader,
    required SetlistExportSourceLoader setlistLoader,
    required LinkedAudioClipLoader linkedAudioClipLoader,
    ClickSoundClipLoader? clickSoundClipLoader,
    FfmpegAudioExportClient? ffmpegAudioExportClient,
    LinkedAudioPathRepairService? linkedAudioPathRepairService,
  }) {
    return ExportEngine(
      sourceResolver: ExportProjectSourceResolver(
        songLoader: songLoader,
        setlistLoader: setlistLoader,
        linkedAudioExportAugmenter: LinkedAudioExportAugmenter(
          linkedAudioClipLoader: linkedAudioClipLoader,
        ),
        clickTrackExportAugmenter: clickSoundClipLoader != null
            ? ClickTrackExportAugmenter(
                clickSoundClipLoader: clickSoundClipLoader,
              )
            : null,
        audioCueExportAugmenter: const AudioCueExportAugmenter(),
        linkedAudioPathRepairService: linkedAudioPathRepairService,
      ),
      offlineAudioRenderer: const OfflinePcmAudioRenderer(),
      audioExportTranscoder: FfmpegAudioExportTranscoder(
        ffmpegAudioExportClient: ffmpegAudioExportClient,
      ),
    );
  }
}
