import '../../core/domain/song.dart';
import '../../core/domain/audio_cue.dart';
import '../../core/domain/song_beatmap.dart';

sealed class LivePlaybackPlan {
  const LivePlaybackPlan();
}

class SongPlaybackPlan extends LivePlaybackPlan {
  const SongPlaybackPlan({
    required this.song,
    required this.beatmap,
    required this.shouldPlayLinkedAudio,
  });

  final Song song;
  final SongBeatmap beatmap;
  final bool shouldPlayLinkedAudio;
}

class SetlistPlaybackPlan extends LivePlaybackPlan {
  const SetlistPlaybackPlan({
    required this.segments,
    required this.totalPlayableSongs,
  });

  final List<SetlistPlaybackSegment> segments;
  final int totalPlayableSongs;
}

sealed class SetlistPlaybackSegment {
  const SetlistPlaybackSegment();
}

class SetlistSongSegment extends SetlistPlaybackSegment {
  const SetlistSongSegment({
    required this.song,
    required this.songTitle,
    required this.songIndex,
    required this.beatmap,
    required this.shouldPlayLinkedAudio,
  });

  final Song song;
  final String songTitle;
  final int songIndex;
  final SongBeatmap beatmap;
  final bool shouldPlayLinkedAudio;
}

class SetlistCountInSegment extends SetlistPlaybackSegment {
  const SetlistCountInSegment({
    required this.songTitle,
    required this.songIndex,
    required this.beatmap,
  });

  final String songTitle;
  final int songIndex;
  final SongBeatmap beatmap;
}

class SetlistWaitSegment extends SetlistPlaybackSegment {
  const SetlistWaitSegment({
    required this.songTitle,
    required this.songIndex,
    required this.durationSeconds,
  });

  final String songTitle;
  final int songIndex;
  final int durationSeconds;
}

class SetlistManualSegment extends SetlistPlaybackSegment {
  const SetlistManualSegment({
    required this.songTitle,
    required this.songIndex,
  });

  final String songTitle;
  final int songIndex;
}

class SetlistAudioCueSegment extends SetlistPlaybackSegment {
  const SetlistAudioCueSegment({
    required this.songTitle,
    required this.songIndex,
    required this.audioCue,
  });

  final String songTitle;
  final int songIndex;
  final AudioCue audioCue;
}
