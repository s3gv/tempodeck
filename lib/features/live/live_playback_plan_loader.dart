import '../../core/domain/setlist.dart';
import '../../core/domain/song.dart';
import '../../core/domain/song_beatmap.dart';
import '../../core/repositories/song_repository.dart';
import 'live_playback_plan.dart';
import 'live_view_context.dart';

class LivePlaybackPlanLoader {
  const LivePlaybackPlanLoader({
    required SongRepository songRepository,
  }) : _songRepository = songRepository;

  final SongRepository _songRepository;

  Future<LivePlaybackPlan> load(LiveViewContext context) async {
    return switch (context) {
      SongViewContext(:final song) => _loadSong(song),
      SetlistViewContext(:final setlist) => _loadSetlist(setlist),
      MetronomeViewContext() => throw StateError(
          'Metronome context does not use a persisted playback plan.',
        ),
    };
  }

  Future<SongPlaybackPlan> _loadSong(Song song) async {
    final persistedSong = await _songRepository.loadSong(song.id);
    return SongPlaybackPlan(
      song: persistedSong,
      beatmap: await _songRepository.loadSongBeatmap(song.id),
      shouldPlayLinkedAudio: true,
    );
  }

  Future<SetlistPlaybackPlan> _loadSetlist(Setlist setlist) async {
    final playableItems = setlist.items
        .where((item) => item.playbackEnabled)
        .toList(growable: false);
    final segments = <SetlistPlaybackSegment>[];

    for (var playableIndex = 0;
        playableIndex < playableItems.length;
        playableIndex += 1) {
      final item = playableItems[playableIndex];
      final song = await _songRepository.loadSong(item.songId);
      final beatmap = await _songRepository.loadSongBeatmap(item.songId);

      for (final step in item.transitionSteps) {
        switch (step.type) {
          case SetlistTransitionStepType.countInBars:
            segments.add(
              SetlistCountInSegment(
                songTitle: item.songTitle,
                songIndex: playableIndex + 1,
                beatmap: _buildCountInBeatmap(
                  beatmap: beatmap,
                  barCount: step.value,
                ),
              ),
            );
          case SetlistTransitionStepType.pauseTimer:
            segments.add(
              SetlistWaitSegment(
                songTitle: item.songTitle,
                songIndex: playableIndex + 1,
                durationSeconds: step.value,
              ),
            );
          case SetlistTransitionStepType.manual:
            segments.add(
              SetlistManualSegment(
                songTitle: item.songTitle,
                songIndex: playableIndex + 1,
              ),
            );
          case SetlistTransitionStepType.audio:
            final audioCue = step.audioCue;
            if (audioCue == null) {
              throw StateError('Audio transition step requires an audio cue.');
            }
            segments.add(
              SetlistAudioCueSegment(
                songTitle: item.songTitle,
                songIndex: playableIndex + 1,
                audioCue: audioCue,
              ),
            );
        }
      }

      // Strip the song's own count-in bars — in setlist mode, only transition
      // step count-ins are used. The original beatmap (with count-in) is kept
      // for building transition count-in segments above.
      segments.add(
        SetlistSongSegment(
          song: song,
          songTitle: item.songTitle,
          songIndex: playableIndex + 1,
          beatmap: beatmap.withoutCountIn(),
          shouldPlayLinkedAudio: item.playAttachedAudio,
        ),
      );
    }

    return SetlistPlaybackPlan(
      segments: List<SetlistPlaybackSegment>.unmodifiable(segments),
      totalPlayableSongs: playableItems.length,
    );
  }

  SongBeatmap _buildCountInBeatmap({
    required SongBeatmap beatmap,
    required int barCount,
  }) {
    if (barCount <= 0) {
      throw ArgumentError.value(barCount, 'barCount', 'must be at least 1');
    }

    final firstSongEntry = beatmap.firstSongEntry;
    final entries = <SongBeatmapEntry>[
      for (var countInBar = barCount; countInBar >= 1; countInBar -= 1)
        SongBeatmapEntry(
          playbackBarIndex: barCount - countInBar + 1,
          barLabel: '-$countInBar',
          barKind: SongBeatmapBarKind.countIn,
          repeatPass: 1,
          notationBarIndex: null,
          bpm: firstSongEntry.bpm,
          beatsPerBar: firstSongEntry.beatsPerBar,
          beatUnit: firstSongEntry.beatUnit,
          subdivision: firstSongEntry.subdivision,
          accentPattern: firstSongEntry.accentPattern,
          events: const [],
          audioCueTriggers: const [],
        ),
      // Append the first song bar so count-in playback can detect the exact
      // handoff tick into the real song without consulting any parallel logic.
      SongBeatmapEntry(
        playbackBarIndex: barCount + 1,
        barLabel: firstSongEntry.barLabel,
        barKind: firstSongEntry.barKind,
        repeatPass: firstSongEntry.repeatPass,
        notationBarIndex: firstSongEntry.notationBarIndex,
        loopId: firstSongEntry.loopId,
        alternativeEndingId: firstSongEntry.alternativeEndingId,
        alternativeEndingBarIndex: firstSongEntry.alternativeEndingBarIndex,
        bpm: firstSongEntry.bpm,
        beatsPerBar: firstSongEntry.beatsPerBar,
        beatUnit: firstSongEntry.beatUnit,
        subdivision: firstSongEntry.subdivision,
        accentPattern: firstSongEntry.accentPattern,
        events: const [],
        audioCueTriggers: const [],
      ),
    ];

    return SongBeatmap(entries: entries);
  }
}
