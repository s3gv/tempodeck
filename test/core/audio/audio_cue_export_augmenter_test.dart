import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/audio_cue_export_augmenter.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

SongBeatmapEntry _entry({
  required int playbackBarIndex,
  int bpm = 120,
  int beatsPerBar = 4,
  List<SongBeatmapAudioCueTrigger> audioCueTriggers = const [],
}) {
  return SongBeatmapEntry(
    playbackBarIndex: playbackBarIndex,
    barLabel: '$playbackBarIndex',
    barKind: SongBeatmapBarKind.notation,
    repeatPass: 1,
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    beatUnit: 4,
    subdivision: Subdivision.one,
    accentPattern: List.filled(beatsPerBar, AccentLevel.normal),
    events: const [],
    audioCueTriggers: audioCueTriggers,
  );
}

SongBeatmap _beatmap(List<SongBeatmapEntry> entries) {
  return SongBeatmap(entries: entries);
}

/// Duration of one bar at [bpm] with [beatsPerBar] beats and [beatUnit].
Duration _barDuration({int bpm = 120, int beatsPerBar = 4, int beatUnit = 4}) {
  final quarterNoteMicros = Duration.microsecondsPerMinute / bpm;
  final beatMicros = (quarterNoteMicros * (4 / beatUnit)).round();
  return Duration(microseconds: beatMicros * beatsPerBar);
}

void main() {
  late AudioCueExportAugmenter augmenter;

  setUp(() {
    augmenter = const AudioCueExportAugmenter();
  });

  test('generates events for tone cues', () async {
    final beatmap = _beatmap([
      _entry(playbackBarIndex: 1),
      _entry(playbackBarIndex: 2),
      _entry(
        playbackBarIndex: 3,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '3',
            label: 'Interval',
            audioCue: AudioCue(type: AudioCueType.intervalSignal),
          ),
        ],
      ),
      _entry(playbackBarIndex: 4),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    expect(result.audioEvents.length, 1);
    // Cue fires at bar 3 → offset = 2 bars of elapsed time.
    final expectedOffset = _barDuration() * 2;
    expect(result.audioEvents.first.offset, expectedOffset);
    expect(result.audioEvents.first.clip.channelCount, 2);
  });

  test('skips voice cues', () async {
    final beatmap = _beatmap([
      _entry(playbackBarIndex: 1),
      _entry(
        playbackBarIndex: 2,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '2',
            label: 'Voice',
            audioCue: AudioCue(
              type: AudioCueType.voice,
              voiceText: 'Hello',
            ),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    expect(result.audioEvents, isEmpty);
  });

  test('skips custom file cues and adds warning', () async {
    final beatmap = _beatmap([
      _entry(playbackBarIndex: 1),
      _entry(
        playbackBarIndex: 2,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '2',
            label: 'Custom',
            audioCue: AudioCue(
              type: AudioCueType.customFile,
              customFilePath: '/some/file.wav',
            ),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    expect(result.audioEvents, isEmpty);
    expect(result.warnings, contains(customFileCueExportWarning));
  });

  test('places cue at correct offset based on bar position', () async {
    // Cue on bar 3 at 120 bpm, 4/4 → offset = 2 bars = 4s.
    final beatmap = _beatmap([
      _entry(playbackBarIndex: 1),
      _entry(playbackBarIndex: 2),
      _entry(
        playbackBarIndex: 3,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '3',
            label: 'LowPulse',
            audioCue: AudioCue(type: AudioCueType.lowPulse),
          ),
        ],
      ),
      _entry(playbackBarIndex: 4),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    final expectedOffset = _barDuration() * 2;
    expect(result.audioEvents.first.offset, expectedOffset);
  });

  test('applies cue gain and per-cue volume', () async {
    final beatmap = _beatmap([
      _entry(playbackBarIndex: 1),
      _entry(
        playbackBarIndex: 2,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '2',
            label: 'Quiet',
            audioCue: AudioCue(
              type: AudioCueType.midPulse,
              volumePercent: 50,
            ),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    // 0.8 (master cue gain) × 0.5 (per-cue volume) = 0.4
    expect(result.audioEvents.first.gain, closeTo(0.4, 0.001));
  });

  test('count-in bars contribute to elapsed offset', () async {
    // Count-in bar followed by a notation bar with a cue.
    final beatmap = _beatmap([
      const SongBeatmapEntry(
        playbackBarIndex: 1,
        barLabel: 'CI',
        barKind: SongBeatmapBarKind.countIn,
        repeatPass: 1,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        subdivision: Subdivision.one,
        accentPattern: [
          AccentLevel.high,
          AccentLevel.normal,
          AccentLevel.normal,
          AccentLevel.normal,
        ],
        events: [],
        audioCueTriggers: [],
      ),
      _entry(
        playbackBarIndex: 2,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '1',
            label: 'AtStart',
            audioCue: AudioCue(type: AudioCueType.highPulse),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 12),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    // Cue at bar 2 → offset = 1 count-in bar elapsed.
    expect(result.audioEvents.first.offset, _barDuration());
  });

  test('preserves existing events and warnings', () async {
    final beatmap = _beatmap([
      _entry(playbackBarIndex: 1),
      _entry(
        playbackBarIndex: 2,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '2',
            label: 'Test',
            audioCue: AudioCue(type: AudioCueType.maxSignal),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
      warnings: const ['existing warning'],
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    expect(result.warnings, contains('existing warning'));
    expect(result.audioEvents.length, 1);
  });

  test('applies timelineOffset to cue events', () async {
    final beatmap = _beatmap([
      _entry(
        playbackBarIndex: 1,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '1',
            label: 'AtStart',
            audioCue: AudioCue(type: AudioCueType.highPulse),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );
    const offset = Duration(seconds: 5);

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
      timelineOffset: offset,
    );

    expect(result.audioEvents.first.offset, offset);
  });

  test('accounts for beatUnit in bar duration for cue placement', () async {
    // 120 bpm, 4 beats, beatUnit=8 → bar = 4 × 250ms = 1000ms.
    // Cue on bar 2 → offset = 1000ms.
    final beatmap = _beatmap([
      SongBeatmapEntry(
        playbackBarIndex: 1,
        barLabel: '1',
        barKind: SongBeatmapBarKind.notation,
        repeatPass: 1,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 8,
        subdivision: Subdivision.one,
        accentPattern: List.filled(4, AccentLevel.normal),
        events: const [],
        audioCueTriggers: const [],
      ),
      SongBeatmapEntry(
        playbackBarIndex: 2,
        barLabel: '2',
        barKind: SongBeatmapBarKind.notation,
        repeatPass: 1,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 8,
        subdivision: Subdivision.one,
        accentPattern: List.filled(4, AccentLevel.normal),
        events: const [],
        audioCueTriggers: const [
          SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '2',
            label: 'Test',
            audioCue: AudioCue(type: AudioCueType.highPulse),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 0.8,
    );

    // At 120 bpm with beatUnit=8: beat = 250ms, bar = 1000ms.
    // Cue is at bar 2, so offset = 1 bar = 1000ms.
    expect(result.audioEvents.first.offset.inMilliseconds, 1000);
  });

  test('generates multiple cue events across bars', () async {
    final beatmap = _beatmap([
      _entry(
        playbackBarIndex: 1,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-1',
            sourceBarLabel: '1',
            label: 'First',
            audioCue: AudioCue(type: AudioCueType.lowPulse),
          ),
        ],
      ),
      _entry(playbackBarIndex: 2),
      _entry(
        playbackBarIndex: 3,
        audioCueTriggers: [
          const SongBeatmapAudioCueTrigger(
            sourceEventId: 'e-2',
            sourceBarLabel: '3',
            label: 'Second',
            audioCue: AudioCue(type: AudioCueType.highPulse),
          ),
        ],
      ),
    ]);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: beatmap,
      cueGain: 1.0,
    );

    expect(result.audioEvents.length, 2);
    expect(result.audioEvents[0].offset, Duration.zero);
    expect(result.audioEvents[1].offset, _barDuration() * 2);
  });
}
