import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

void main() {
  test('builds beatmap entries from notation bars, repeats, and endings', () {
    final beatmap = const SongPlaybackBeatmapBuilder().build(
      Song(
        id: 'song-1',
        title: 'Beatmap Song',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 2,
        endBar: 6,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 5,
            bpm: 90,
            beatsPerBar: 3,
            beatUnit: 8,
          ),
        ],
        loops: const [
          SongLoop(
            id: 'loop-1',
            startBar: 2,
            endBar: 4,
            repeatCount: 1,
            alternativeEndings: [
              SongLoopAlternativeEnding(
                id: 'ending-1',
                repeatPass: 2,
                lengthBars: 2,
                tempoChanges: [
                  SongTempoChange(
                    id: 'ending-tempo-1',
                    barIndex: 2,
                    bpm: 110,
                    beatsPerBar: 5,
                    beatUnit: 8,
                  ),
                ],
                songEvents: [
                  SongEvent(
                    id: 'ending-event-1',
                    barIndex: 2,
                    label: 'Ending hit',
                    audioCue: AudioCue(
                      type: AudioCueType.highPulse,
                      volumePercent: 70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        songEvents: const [
          SongEvent(
            id: 'event-1',
            barIndex: 5,
            label: 'Chorus',
            audioCue: AudioCue(
              type: AudioCueType.voice,
              voiceText: 'Chorus',
              voiceIdentifier: 'en-US',
            ),
            audioCueBarsBefore: 1,
          ),
        ],
        beatPatterns: const [
          SongBarBeatPattern(
            id: 'pattern-1',
            barIndex: 2,
            repeatPass: 2,
            accents: [
              AccentLevel.high,
              AccentLevel.low,
              AccentLevel.low,
              AccentLevel.low,
              AccentLevel.normal,
              AccentLevel.normal,
              AccentLevel.normal,
              AccentLevel.normal,
            ],
            subdivision: Subdivision.two,
          ),
        ],
      ),
    );

    expect(beatmap.countInBarCount, 2);
    expect(beatmap.totalPlaybackBars, 13);
    expect(beatmap.entryForPlaybackBar(1).barLabel, '-2');
    expect(beatmap.entryForPlaybackBar(2).barLabel, '-1');

    final repeatedBar = beatmap.entryForPlaybackBar(7);
    expect(repeatedBar.displayBarIndex, 2);
    expect(repeatedBar.repeatPass, 2);
    expect(repeatedBar.barLabel, '2.2');
    expect(repeatedBar.subdivision, Subdivision.two);
    expect(repeatedBar.accentPattern.first, AccentLevel.high);
    expect(repeatedBar.accentPattern.length, 8);

    final endingBar = beatmap.entryForPlaybackBar(10);
    expect(endingBar.barKind, SongBeatmapBarKind.alternativeEnding);
    expect(endingBar.barLabel, '1.1.2');

    final changedBar = beatmap.entryForPlaybackBar(12);
    expect(changedBar.barLabel, '5');
    expect(changedBar.bpm, 90);
    expect(changedBar.beatsPerBar, 3);
    expect(changedBar.beatUnit, 8);

    final secondEndingBar = beatmap.entryForPlaybackBar(11);
    expect(secondEndingBar.bpm, 110);
    expect(secondEndingBar.beatsPerBar, 5);
    expect(secondEndingBar.beatUnit, 8);
    expect(secondEndingBar.barLabel, '1.2.2');
    expect(
      secondEndingBar.events.map((event) => event.label),
      contains('Ending hit'),
    );

    final triggerBar = beatmap.entryForPlaybackBar(11);
    expect(
      triggerBar.audioCueTriggers.map((trigger) => trigger.sourceBarLabel),
      contains('5'),
    );
    expect(
      triggerBar.audioCueTriggers.map((trigger) => trigger.audioCue.type),
      contains(AudioCueType.voice),
    );
  });
}
