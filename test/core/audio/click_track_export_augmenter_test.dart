import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/click_track_export_augmenter.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

final _stereoClip = ExportAudioClip(
  samples: Float32List.fromList([0.5, 0.5]),
  sampleRate: 44100,
  channelCount: 2,
);

class FakeClickSoundClipLoader implements ClickSoundClipLoader {
  final loadedVariants = <ClickSoundVariant>[];

  @override
  Future<ExportAudioClip> loadClip(
    ClickSoundSet soundSet,
    ClickSoundVariant variant,
  ) async {
    loadedVariants.add(variant);
    return _stereoClip;
  }
}

const _beatmapBuilder = SongPlaybackBeatmapBuilder();

Song _simpleSong({
  int endBar = 4,
  int startBpm = 120,
  int beatsPerBar = 4,
  int countInBars = 0,
  List<SongBarBeatPattern> beatPatterns = const [],
}) {
  return Song(
    id: 'song-1',
    title: 'Test',
    createdAt: DateTime(2024),
    startBpm: startBpm,
    beatsPerBar: beatsPerBar,
    beatUnit: 4,
    countInBars: countInBars,
    endBar: endBar,
    beatPatterns: beatPatterns,
  );
}

SongBeatmap _beatmapFor(Song song) => _beatmapBuilder.build(song);

void main() {
  late FakeClickSoundClipLoader loader;
  late ClickTrackExportAugmenter augmenter;

  setUp(() {
    loader = FakeClickSoundClipLoader();
    augmenter = ClickTrackExportAugmenter(clickSoundClipLoader: loader);
  });

  test('generates one click per beat for a simple song', () async {
    final song = _simpleSong(endBar: 2, beatsPerBar: 4);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 4),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // 2 bars × 4 beats = 8 clicks
    expect(result.audioEvents.length, 8);
  });

  test('includes count-in clicks from beatmap', () async {
    final song = _simpleSong(endBar: 2, beatsPerBar: 4, countInBars: 1);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 6),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // 1 count-in bar × 4 + 2 bars × 4 = 12 clicks
    expect(result.audioEvents.length, 12);

    // Count-in clicks start at offset 0.
    expect(result.audioEvents.first.offset, Duration.zero);
  });

  test('does not include count-in clicks when song has none', () async {
    final song = _simpleSong(endBar: 2, beatsPerBar: 4, countInBars: 0);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 4),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // Only song bars: 2 × 4 = 8
    expect(result.audioEvents.length, 8);
  });

  test('skips muted beats', () async {
    final song = _simpleSong(
      endBar: 1,
      beatsPerBar: 4,
      beatPatterns: [
        const SongBarBeatPattern(
          id: 'bp-1',
          barIndex: 1,
          accents: [
            AccentLevel.high,
            AccentLevel.mute,
            AccentLevel.normal,
            AccentLevel.mute,
          ],
          subdivision: Subdivision.one,
        ),
      ],
    );
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 2),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // 2 of 4 beats are muted → 2 clicks
    expect(result.audioEvents.length, 2);
  });

  test('generates subdivision pulses', () async {
    final song = _simpleSong(
      endBar: 1,
      beatsPerBar: 2,
      beatPatterns: [
        const SongBarBeatPattern(
          id: 'bp-1',
          barIndex: 1,
          accents: [AccentLevel.high, AccentLevel.normal],
          subdivision: Subdivision.two,
        ),
      ],
    );
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 1),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // 2 beats × (1 accent + 1 subdivision) = 4 events
    expect(result.audioEvents.length, 4);
  });

  test('applies gain to all events', () async {
    final song = _simpleSong(endBar: 1, beatsPerBar: 2);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 1),
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.6,
    );

    for (final event in result.audioEvents) {
      expect(event.gain, closeTo(0.6, 0.001));
    }
  });

  test('preserves existing audio events', () async {
    final existingEvent = ExportAudioEvent(
      offset: Duration.zero,
      clip: _stereoClip,
    );
    final song = _simpleSong(endBar: 1, beatsPerBar: 2);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 1),
      audioEvents: [existingEvent],
    );

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // 1 existing + 2 new clicks
    expect(result.audioEvents.length, 3);
    expect(result.audioEvents.first, existingEvent);
  });

  test('accounts for beatUnit in beat duration', () async {
    // 120 bpm with beatUnit=8 means each beat is an eighth note:
    // duration = (60/120) * (4/8) = 0.25s per beat.
    // Compare to beatUnit=4: (60/120) * (4/4) = 0.5s per beat.
    final songQuarter = Song(
      id: 'song-1',
      title: 'Test',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 1,
    );
    final songEighth = Song(
      id: 'song-2',
      title: 'Test',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 8,
      countInBars: 0,
      endBar: 1,
    );
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 10),
    );

    final resultQuarter = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(songQuarter),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );
    final resultEighth = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(songEighth),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
    );

    // Both have 4 beats → 4 click events.
    expect(resultQuarter.audioEvents.length, 4);
    expect(resultEighth.audioEvents.length, 4);

    // Quarter note beat spacing at 120 bpm: 500ms.
    expect(
      resultQuarter.audioEvents[1].offset.inMilliseconds,
      500,
    );
    // Eighth note beat spacing at 120 bpm: 250ms.
    expect(
      resultEighth.audioEvents[1].offset.inMilliseconds,
      250,
    );
  });

  test('applies timelineOffset to all events', () async {
    final song = _simpleSong(endBar: 1, beatsPerBar: 2, startBpm: 120);
    final project = ResolvedExportProject(
      source: SongExportSource('song-1'),
      duration: const Duration(seconds: 5),
    );
    final offset = const Duration(seconds: 3);

    final result = await augmenter.augment(
      project: project,
      beatmap: _beatmapFor(song),
      clickSoundSet: ClickSoundSet.tock,
      metronomeGain: 0.8,
      timelineOffset: offset,
    );

    // First click should be at the timeline offset.
    expect(result.audioEvents.first.offset, offset);
  });
}
