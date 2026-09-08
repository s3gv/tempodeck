import '../domain/audio_cue.dart';
import '../domain/song_beatmap.dart';
import 'audio_cue_tone_library.dart';
import 'beat_duration.dart';
import 'export_audio_clip_utils.dart';
import 'export_engine.dart';
import 'wave_file_decoder.dart';

const String customFileCueExportWarning =
    'Custom file cues cannot be exported and will be skipped.';

class AudioCueExportAugmenter {
  const AudioCueExportAugmenter({
    WaveFileDecoder? waveFileDecoder,
  }) : _waveFileDecoder = waveFileDecoder ?? const WaveFileDecoder();

  final WaveFileDecoder _waveFileDecoder;

  Future<ResolvedExportProject> augment({
    required ResolvedExportProject project,
    required SongBeatmap beatmap,
    required double cueGain,
    Duration timelineOffset = Duration.zero,
  }) async {
    final events = <ExportAudioEvent>[];
    final clipCache = <AudioCueType, ExportAudioClip>{};
    var hasCustomFileCue = false;
    var elapsed = timelineOffset;

    for (final entry in beatmap.entries) {
      for (final trigger in entry.audioCueTriggers) {
        final audioCue = trigger.audioCue;

        if (audioCue.type == AudioCueType.voice) {
          continue;
        }

        if (audioCue.type == AudioCueType.customFile) {
          hasCustomFileCue = true;
          continue;
        }

        final clip =
            clipCache[audioCue.type] ?? await _buildToneClip(audioCue.type);
        clipCache[audioCue.type] = clip;

        final cueSpecificGain = audioCue.volumePercent / 100;
        events.add(
          ExportAudioEvent(
            offset: elapsed,
            clip: clip,
            gain: cueGain * cueSpecificGain,
          ),
        );
      }

      final bd = beatDuration(bpm: entry.bpm, beatUnit: entry.beatUnit);
      elapsed += Duration(
        microseconds: bd.inMicroseconds * entry.beatsPerBar,
      );
    }

    final warnings = hasCustomFileCue
        ? [...project.warnings, customFileCueExportWarning]
        : project.warnings;

    return project.copyWith(
      audioEvents: [...project.audioEvents, ...events],
      warnings: warnings.toSet().toList(growable: false),
    );
  }

  Future<ExportAudioClip> _buildToneClip(AudioCueType type) async {
    final spec = AudioCueToneLibrary.specFor(type);
    if (spec == null) {
      throw ArgumentError.value(
        type,
        'type',
        'No tone spec found for cue type.',
      );
    }

    final waveBytes = AudioCueToneLibrary.buildWaveFile(spec);
    final monoClip = _waveFileDecoder.decode(waveBytes);
    return ensureStereo(monoClip);
  }

}
