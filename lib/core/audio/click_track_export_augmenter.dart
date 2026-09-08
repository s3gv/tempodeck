import 'package:logging/logging.dart';

import '../domain/accent_level.dart';
import '../domain/click_sound_set.dart';
import '../domain/song_beatmap.dart';
import '../domain/subdivision.dart';
import 'beat_duration.dart';
import 'click_sound_set_assets.dart';
import 'export_audio_clip_utils.dart';
import 'export_engine.dart';

final _logger = Logger('ClickTrackExportAugmenter');

abstract class ClickSoundClipLoader {
  Future<ExportAudioClip> loadClip(
    ClickSoundSet soundSet,
    ClickSoundVariant variant,
  );
}

class ClickTrackExportAugmenter {
  const ClickTrackExportAugmenter({
    required ClickSoundClipLoader clickSoundClipLoader,
  }) : _clickSoundClipLoader = clickSoundClipLoader;

  final ClickSoundClipLoader _clickSoundClipLoader;

  Future<ResolvedExportProject> augment({
    required ResolvedExportProject project,
    required SongBeatmap beatmap,
    required ClickSoundSet clickSoundSet,
    required double metronomeGain,
    Duration timelineOffset = Duration.zero,
  }) async {
    final clips = await _loadClips(
      clickSoundSet,
      targetSampleRate: project.outputFormat.sampleRate,
    );
    final events = <ExportAudioEvent>[];
    var elapsed = timelineOffset;

    for (final entry in beatmap.entries) {
      final bd = beatDuration(bpm: entry.bpm, beatUnit: entry.beatUnit);
      final subdivisionCount = entry.subdivision.pulseCount;
      final pulseDuration = _pulseDuration(bd, subdivisionCount);

      for (var beat = 0; beat < entry.beatsPerBar; beat++) {
        final accent = beat < entry.accentPattern.length
            ? entry.accentPattern[beat]
            : (beat == 0 ? AccentLevel.high : AccentLevel.normal);

        if (accent == AccentLevel.mute) {
          elapsed += bd;
          continue;
        }

        final variant = _variantForAccent(accent);
        final clip = clips[variant];
        if (clip != null) {
          events.add(
            ExportAudioEvent(
              offset: elapsed,
              clip: clip,
              gain: metronomeGain,
            ),
          );
        }

        // Subdivision pulses after the first beat pulse.
        for (var pulse = 1; pulse < subdivisionCount; pulse++) {
          final pulseOffset =
              elapsed + Duration(microseconds: pulseDuration.inMicroseconds * pulse);
          final subdivisionClip = clips[ClickSoundVariant.subdivision];
          if (subdivisionClip != null) {
            events.add(
              ExportAudioEvent(
                offset: pulseOffset,
                clip: subdivisionClip,
                gain: metronomeGain,
              ),
            );
          }
        }

        elapsed += bd;
      }
    }

    if (events.length >= 2) {
      final firstFew = events.take(5).map(
        (e) => '${e.offset.inMilliseconds}ms',
      );
      final lastFew = events.length > 10
          ? events.skip(events.length - 3).map(
              (e) => '${e.offset.inMilliseconds}ms',
            )
          : <String>[];
      _logger.info(
        'Generated ${events.length} click events. '
        'First offsets: [${firstFew.join(', ')}]'
        '${lastFew.isNotEmpty ? ', last offsets: [${lastFew.join(', ')}]' : ''}',
      );
    }

    return project.copyWith(
      audioEvents: [...project.audioEvents, ...events],
    );
  }

  Future<Map<ClickSoundVariant, ExportAudioClip>> _loadClips(
    ClickSoundSet soundSet, {
    required int targetSampleRate,
  }) async {
    final clips = <ClickSoundVariant, ExportAudioClip>{};
    for (final variant in ClickSoundVariant.values) {
      final clip = await _clickSoundClipLoader.loadClip(soundSet, variant);
      clips[variant] = resampleClip(clip, targetSampleRate);
    }
    return clips;
  }

  ClickSoundVariant _variantForAccent(AccentLevel accent) {
    return switch (accent) {
      AccentLevel.high => ClickSoundVariant.accentHigh,
      AccentLevel.normal => ClickSoundVariant.normal,
      AccentLevel.low => ClickSoundVariant.accentLow,
      AccentLevel.mute => ClickSoundVariant.normal,
    };
  }

  Duration _pulseDuration(Duration beatDuration, int subdivisionCount) {
    return Duration(
      microseconds: (beatDuration.inMicroseconds / subdivisionCount).round(),
    );
  }
}
