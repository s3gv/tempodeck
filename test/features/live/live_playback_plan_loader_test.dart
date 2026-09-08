import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/features/live/live_playback_plan.dart';
import 'package:tempodeck/features/live/live_playback_plan_loader.dart';
import 'package:tempodeck/features/live/live_view_context.dart';

void main() {
  test('loads a persisted song playback plan', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime(2026),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 8,
    );
    final beatmap = SongBeatmap(
      entries: const [
        SongBeatmapEntry(
          playbackBarIndex: 1,
          barLabel: '1',
          barKind: SongBeatmapBarKind.notation,
          repeatPass: 1,
          notationBarIndex: 1,
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [],
          events: [],
          audioCueTriggers: [],
        ),
      ],
    );
    final loader = LivePlaybackPlanLoader(
      songRepository: _FakeSongRepository(
        songs: [song],
        beatmaps: {'song-1': beatmap},
      ),
    );

    final plan = await loader.load(SongViewContext(song: song));

    expect(plan, isA<SongPlaybackPlan>());
    final songPlan = plan as SongPlaybackPlan;
    expect(songPlan.song.id, 'song-1');
    expect(songPlan.song.title, 'Warmup');
    expect(songPlan.beatmap.entries.single.barLabel, '1');
    expect(songPlan.shouldPlayLinkedAudio, isTrue);
  });

  test('loads the persisted song aggregate instead of using a stale context copy',
      () async {
    final staleContextSong = Song(
      id: 'song-1',
      title: 'Unsaved Draft',
      createdAt: DateTime(2026),
      startBpm: 90,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 8,
    );
    final persistedSong = Song(
      id: 'song-1',
      title: 'Persisted Song',
      createdAt: DateTime(2026),
      startBpm: 120,
      beatsPerBar: 9,
      beatUnit: 8,
      countInBars: 0,
      endBar: 8,
    );
    final beatmap = SongBeatmap(
      entries: const [
        SongBeatmapEntry(
          playbackBarIndex: 1,
          barLabel: '1',
          barKind: SongBeatmapBarKind.notation,
          repeatPass: 1,
          notationBarIndex: 1,
          bpm: 120,
          beatsPerBar: 9,
          beatUnit: 8,
          subdivision: Subdivision.one,
          accentPattern: [],
          events: [],
          audioCueTriggers: [],
        ),
      ],
    );
    final loader = LivePlaybackPlanLoader(
      songRepository: _FakeSongRepository(
        songs: [persistedSong],
        beatmaps: {'song-1': beatmap},
      ),
    );

    final plan = await loader.load(SongViewContext(song: staleContextSong));

    expect(plan, isA<SongPlaybackPlan>());
    final songPlan = plan as SongPlaybackPlan;
    expect(songPlan.song.title, 'Persisted Song');
    expect(songPlan.song.startBpm, 120);
    expect(songPlan.song.beatsPerBar, 9);
    expect(songPlan.song.beatUnit, 8);
    expect(songPlan.beatmap.entries.single.beatsPerBar, 9);
    expect(songPlan.beatmap.entries.single.beatUnit, 8);
  });

  test('loads a deterministic setlist playback plan from persisted beatmaps',
      () async {
    final firstBeatmap = SongBeatmap(
      entries: const [
        SongBeatmapEntry(
          playbackBarIndex: 1,
          barLabel: '1',
          barKind: SongBeatmapBarKind.notation,
          repeatPass: 1,
          notationBarIndex: 1,
          bpm: 100,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [],
          events: [],
          audioCueTriggers: [],
        ),
      ],
    );
    final secondBeatmap = SongBeatmap(
      entries: const [
        SongBeatmapEntry(
          playbackBarIndex: 1,
          barLabel: '-2',
          barKind: SongBeatmapBarKind.countIn,
          repeatPass: 1,
          bpm: 160,
          beatsPerBar: 3,
          beatUnit: 8,
          subdivision: Subdivision.one,
          accentPattern: [],
          events: [],
          audioCueTriggers: [],
        ),
        SongBeatmapEntry(
          playbackBarIndex: 2,
          barLabel: '1',
          barKind: SongBeatmapBarKind.notation,
          repeatPass: 1,
          notationBarIndex: 1,
          bpm: 160,
          beatsPerBar: 3,
          beatUnit: 8,
          subdivision: Subdivision.one,
          accentPattern: [],
          events: [],
          audioCueTriggers: [],
        ),
      ],
    );
    final loader = LivePlaybackPlanLoader(
      songRepository: _FakeSongRepository(
        songs: [
          Song(
            id: 'song-1',
            title: 'Intro',
            createdAt: DateTime(2026),
            startBpm: 100,
            beatsPerBar: 4,
            beatUnit: 4,
            countInBars: 0,
            endBar: 8,
          ),
          Song(
            id: 'song-2',
            title: 'Finale',
            createdAt: DateTime(2026),
            startBpm: 160,
            beatsPerBar: 3,
            beatUnit: 8,
            countInBars: 2,
            endBar: 8,
          ),
        ],
        beatmaps: {
          'song-1': firstBeatmap,
          'song-2': secondBeatmap,
        },
      ),
    );

    final plan = await loader.load(
      SetlistViewContext(
        setlist: Setlist(
          id: 'setlist-1',
          title: 'Show',
          createdAt: DateTime(2026),
          items: const [
            SetlistItem(
              id: 'item-1',
              songId: 'song-1',
              songTitle: 'Intro',
            ),
            SetlistItem(
              id: 'item-2',
              songId: 'song-2',
              songTitle: 'Finale',
              transitionSteps: [
                SetlistTransitionStep(
                  id: 'count-in',
                  type: SetlistTransitionStepType.countInBars,
                  value: 2,
                ),
                SetlistTransitionStep(
                  id: 'audio',
                  type: SetlistTransitionStepType.audio,
                  value: 0,
                  audioCue: AudioCue(type: AudioCueType.highPulse),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(plan, isA<SetlistPlaybackPlan>());
    final setlistPlan = plan as SetlistPlaybackPlan;
    expect(setlistPlan.totalPlayableSongs, 2);
    expect(setlistPlan.segments, hasLength(4));
    expect(setlistPlan.segments[0], isA<SetlistSongSegment>());
    expect(setlistPlan.segments[1], isA<SetlistCountInSegment>());
    expect(setlistPlan.segments[2], isA<SetlistAudioCueSegment>());
    expect(setlistPlan.segments[3], isA<SetlistSongSegment>());

    final countInSegment = setlistPlan.segments[1] as SetlistCountInSegment;
    expect(countInSegment.songTitle, 'Finale');
    expect(countInSegment.songIndex, 2);
    expect(countInSegment.beatmap.countInBarCount, 2);
    expect(countInSegment.beatmap.entries.first.barLabel, '-2');
    expect(countInSegment.beatmap.firstSongEntry.barLabel, '1');
  });
  group('Setlist transition contract: loaded playback structure only', () {
    test('setlist count-in beatmap derives time signature from loaded song beatmap',
        () async {
      // Song starts at 5/8 @ 180 BPM — the count-in must use this, NOT 4/4.
      final songBeatmap = SongBeatmap(
        entries: const [
          SongBeatmapEntry(
            playbackBarIndex: 1,
            barLabel: '1',
            barKind: SongBeatmapBarKind.notation,
            repeatPass: 1,
            notationBarIndex: 1,
            bpm: 180,
            beatsPerBar: 5,
            beatUnit: 8,
            subdivision: Subdivision.one,
            accentPattern: [],
            events: [],
            audioCueTriggers: [],
          ),
          SongBeatmapEntry(
            playbackBarIndex: 2,
            barLabel: '2',
            barKind: SongBeatmapBarKind.notation,
            repeatPass: 1,
            notationBarIndex: 2,
            bpm: 180,
            beatsPerBar: 5,
            beatUnit: 8,
            subdivision: Subdivision.one,
            accentPattern: [],
            events: [],
            audioCueTriggers: [],
          ),
        ],
      );

      final loader = LivePlaybackPlanLoader(
        songRepository: _FakeSongRepository(
          songs: [
            Song(
              id: 'song-1',
              title: 'Odd Meter Song',
              createdAt: DateTime(2026),
              startBpm: 180,
              beatsPerBar: 5,
              beatUnit: 8,
              countInBars: 0,
              endBar: 2,
            ),
          ],
          beatmaps: {'song-1': songBeatmap},
        ),
      );

      final plan = await loader.load(
        SetlistViewContext(
          setlist: Setlist(
            id: 'setlist-1',
            title: 'Test',
            createdAt: DateTime(2026),
            items: const [
              SetlistItem(
                id: 'item-1',
                songId: 'song-1',
                songTitle: 'Odd Meter Song',
                transitionSteps: [
                  SetlistTransitionStep(
                    id: 'ci',
                    type: SetlistTransitionStepType.countInBars,
                    value: 2,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final setlistPlan = plan as SetlistPlaybackPlan;
      final countIn = setlistPlan.segments[0] as SetlistCountInSegment;

      // Count-in bars must use the loaded song's first entry: 5/8 @ 180 BPM
      for (final entry in countIn.beatmap.entries
          .where((e) => e.barKind == SongBeatmapBarKind.countIn)) {
        expect(
          entry.beatsPerBar,
          5,
          reason: 'count-in bar must be 5/8, not 4/4',
        );
        expect(entry.beatUnit, 8);
        expect(entry.bpm, 180);
      }

      // The last entry in the count-in beatmap is the first song bar
      final firstSongBar = countIn.beatmap.firstSongEntry;
      expect(firstSongBar.beatsPerBar, 5);
      expect(firstSongBar.beatUnit, 8);
      expect(firstSongBar.bpm, 180);
    });

    test('setlist song segment carries beatmap with time event, no revert',
        () async {
      // Song with a time event at bar 3: 4/4 100BPM → 9/8 200BPM
      final song = Song(
        id: 'song-1',
        title: 'Time Event Song',
        createdAt: DateTime(2026),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 't1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );
      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      final loader = LivePlaybackPlanLoader(
        songRepository: _FakeSongRepository(
          songs: [song],
          beatmaps: {'song-1': beatmap},
        ),
      );

      final plan = await loader.load(
        SetlistViewContext(
          setlist: Setlist(
            id: 'setlist-1',
            title: 'Test',
            createdAt: DateTime(2026),
            items: const [
              SetlistItem(
                id: 'item-1',
                songId: 'song-1',
                songTitle: 'Time Event Song',
              ),
            ],
          ),
        ),
      );

      final setlistPlan = plan as SetlistPlaybackPlan;
      final songSegment = setlistPlan.segments[0] as SetlistSongSegment;

      // Bars 1-2: 4/4 @ 100 BPM
      for (final barIndex in [1, 2]) {
        final entry = songSegment.beatmap.entryForPlaybackBar(barIndex);
        expect(entry.beatsPerBar, 4, reason: 'bar $barIndex');
        expect(entry.bpm, 100, reason: 'bar $barIndex');
      }

      // Bars 3-5: 9/8 @ 200 BPM — no revert to 4/4
      for (final barIndex in [3, 4, 5]) {
        final entry = songSegment.beatmap.entryForPlaybackBar(barIndex);
        expect(
          entry.beatsPerBar,
          9,
          reason: 'bar $barIndex must carry 9/8 in setlist segment',
        );
        expect(entry.beatUnit, 8, reason: 'bar $barIndex');
        expect(entry.bpm, 200, reason: 'bar $barIndex');
      }
    });

    test('setlist with all transition types loads from plan, not controller logic',
        () async {
      final song1Beatmap = SongBeatmap(
        entries: const [
          SongBeatmapEntry(
            playbackBarIndex: 1,
            barLabel: '1',
            barKind: SongBeatmapBarKind.notation,
            repeatPass: 1,
            notationBarIndex: 1,
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            events: [],
            audioCueTriggers: [],
          ),
        ],
      );
      final song2Beatmap = SongBeatmap(
        entries: const [
          SongBeatmapEntry(
            playbackBarIndex: 1,
            barLabel: '1',
            barKind: SongBeatmapBarKind.notation,
            repeatPass: 1,
            notationBarIndex: 1,
            bpm: 200,
            beatsPerBar: 7,
            beatUnit: 8,
            subdivision: Subdivision.one,
            accentPattern: [],
            events: [],
            audioCueTriggers: [],
          ),
        ],
      );

      final loader = LivePlaybackPlanLoader(
        songRepository: _FakeSongRepository(
          songs: [
            Song(
              id: 'song-1',
              title: 'Song One',
              createdAt: DateTime(2026),
              startBpm: 120,
              beatsPerBar: 4,
              beatUnit: 4,
              countInBars: 0,
              endBar: 1,
            ),
            Song(
              id: 'song-2',
              title: 'Song Two',
              createdAt: DateTime(2026),
              startBpm: 200,
              beatsPerBar: 7,
              beatUnit: 8,
              countInBars: 0,
              endBar: 1,
            ),
          ],
          beatmaps: {
            'song-1': song1Beatmap,
            'song-2': song2Beatmap,
          },
        ),
      );

      final plan = await loader.load(
        SetlistViewContext(
          setlist: Setlist(
            id: 'setlist-1',
            title: 'Full Transitions',
            createdAt: DateTime(2026),
            items: const [
              SetlistItem(
                id: 'item-1',
                songId: 'song-1',
                songTitle: 'Song One',
              ),
              SetlistItem(
                id: 'item-2',
                songId: 'song-2',
                songTitle: 'Song Two',
                transitionSteps: [
                  SetlistTransitionStep(
                    id: 'ci',
                    type: SetlistTransitionStepType.countInBars,
                    value: 2,
                  ),
                  SetlistTransitionStep(
                    id: 'wait',
                    type: SetlistTransitionStepType.pauseTimer,
                    value: 5,
                  ),
                  SetlistTransitionStep(
                    id: 'manual',
                    type: SetlistTransitionStepType.manual,
                    value: 0,
                  ),
                  SetlistTransitionStep(
                    id: 'audio',
                    type: SetlistTransitionStepType.audio,
                    value: 0,
                    audioCue: AudioCue(type: AudioCueType.highPulse),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final setlistPlan = plan as SetlistPlaybackPlan;

      // Song 1 segment
      expect(setlistPlan.segments[0], isA<SetlistSongSegment>());
      final song1Seg = setlistPlan.segments[0] as SetlistSongSegment;
      expect(song1Seg.beatmap.entries.single.beatsPerBar, 4);

      // Count-in for Song 2: derived from loaded beatmap
      expect(setlistPlan.segments[1], isA<SetlistCountInSegment>());
      final countIn = setlistPlan.segments[1] as SetlistCountInSegment;
      expect(countIn.songTitle, 'Song Two');
      // Count-in bars use Song 2's first entry: 7/8 @ 200 BPM
      for (final entry in countIn.beatmap.entries
          .where((e) => e.barKind == SongBeatmapBarKind.countIn)) {
        expect(
          entry.beatsPerBar,
          7,
          reason: 'count-in must match Song 2 time sig',
        );
        expect(entry.beatUnit, 8);
        expect(entry.bpm, 200);
      }

      // Wait segment
      expect(setlistPlan.segments[2], isA<SetlistWaitSegment>());
      final wait = setlistPlan.segments[2] as SetlistWaitSegment;
      expect(wait.durationSeconds, 5);
      expect(wait.songTitle, 'Song Two');

      // Manual segment
      expect(setlistPlan.segments[3], isA<SetlistManualSegment>());
      expect(
        (setlistPlan.segments[3] as SetlistManualSegment).songTitle,
        'Song Two',
      );

      // Audio cue segment
      expect(setlistPlan.segments[4], isA<SetlistAudioCueSegment>());
      final audioCue = setlistPlan.segments[4] as SetlistAudioCueSegment;
      expect(audioCue.audioCue.type, AudioCueType.highPulse);

      // Song 2 segment: beatmap carries 7/8 @ 200
      expect(setlistPlan.segments[5], isA<SetlistSongSegment>());
      final song2Seg = setlistPlan.segments[5] as SetlistSongSegment;
      expect(song2Seg.beatmap.entries.single.beatsPerBar, 7);
      expect(song2Seg.beatmap.entries.single.beatUnit, 8);
      expect(song2Seg.beatmap.entries.single.bpm, 200);
    });

    test('disabled setlist items are excluded from playback plan', () async {
      final beatmap = SongBeatmap(
        entries: const [
          SongBeatmapEntry(
            playbackBarIndex: 1,
            barLabel: '1',
            barKind: SongBeatmapBarKind.notation,
            repeatPass: 1,
            notationBarIndex: 1,
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            events: [],
            audioCueTriggers: [],
          ),
        ],
      );

      final loader = LivePlaybackPlanLoader(
        songRepository: _FakeSongRepository(
          songs: [
            Song(
              id: 'song-1',
              title: 'Active',
              createdAt: DateTime(2026),
              startBpm: 120,
              beatsPerBar: 4,
              beatUnit: 4,
              countInBars: 0,
              endBar: 1,
            ),
            Song(
              id: 'song-2',
              title: 'Disabled',
              createdAt: DateTime(2026),
              startBpm: 100,
              beatsPerBar: 3,
              beatUnit: 4,
              countInBars: 0,
              endBar: 1,
            ),
          ],
          beatmaps: {
            'song-1': beatmap,
            'song-2': beatmap,
          },
        ),
      );

      final plan = await loader.load(
        SetlistViewContext(
          setlist: Setlist(
            id: 'setlist-1',
            title: 'Test',
            createdAt: DateTime(2026),
            items: const [
              SetlistItem(
                id: 'item-1',
                songId: 'song-1',
                songTitle: 'Active',
              ),
              SetlistItem(
                id: 'item-2',
                songId: 'song-2',
                songTitle: 'Disabled',
                playbackEnabled: false,
              ),
            ],
          ),
        ),
      );

      final setlistPlan = plan as SetlistPlaybackPlan;
      expect(setlistPlan.totalPlayableSongs, 1);
      expect(setlistPlan.segments, hasLength(1));
      expect(
        (setlistPlan.segments[0] as SetlistSongSegment).songTitle,
        'Active',
      );
    });
  });
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository({
    required this.songs,
    required this.beatmaps,
  });

  final List<Song> songs;
  final Map<String, SongBeatmap> beatmaps;

  @override
  Future<List<Song>> getAllSongs() async => songs;

  @override
  Stream<List<Song>> watchAllSongs() => Stream.value(songs);

  @override
  Future<Song?> getSongById(String songId) async {
    for (final song in songs) {
      if (song.id == songId) {
        return song;
      }
    }
    return null;
  }

  @override
  Stream<Song?> watchSongById(String songId) => Stream.value(null);

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) async {
    final beatmap = beatmaps[songId];
    if (beatmap == null) {
      throw StateError('Missing beatmap for $songId');
    }
    return beatmap;
  }

  @override
  Future<void> saveSong(Song song) async {}

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Future<void> deleteSong(String songId) async {}

  @override
  Future<Song> loadSong(String songId) async {
    final song = await getSongById(songId);
    if (song == null) {
      throw StateError('Song not found: $songId');
    }
    return song;
  }
}
