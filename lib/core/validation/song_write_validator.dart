import '../domain/audio_cue.dart';
import '../domain/linked_audio_file.dart';
import '../domain/song.dart';
import 'validation_helpers.dart';

class SongWriteValidator with ValidationHelpers {
  const SongWriteValidator();

  static const int minimumBpm = 20;
  static const int maximumBpm = 320;
  static const Set<int> supportedBeatUnits = {1, 2, 4, 8, 16, 32};
  static const int minimumBeatsPerBar = 1;
  static const int maximumBeatsPerBar = 32;
  static const int minimumCountInBars = 0;
  static const int minimumEndBar = 1;
  static const int minimumBarIndex = 1;
  static const int minimumRepeatCount = 1;
  static const int minimumAlternativeEndingLengthBars = 1;
  static const int minimumAudioCueBarsBefore = 0;
  static const int minimumLinkedAudioOffsetMilliseconds = 0;
  static const int minimumVolumePercent = 0;
  static const int maximumVolumePercent = 100;

  void validate(Song song) {
    if (song.title.trim().isEmpty) {
      throw ArgumentError.value(
        song.title,
        'Song.title',
        'Song.title must not be empty.',
      );
    }
    requireInRange(
      value: song.startBpm,
      minimum: minimumBpm,
      maximum: maximumBpm,
      label: 'Song.startBpm',
    );
    requireInRange(
      value: song.beatsPerBar,
      minimum: minimumBeatsPerBar,
      maximum: maximumBeatsPerBar,
      label: 'Song.beatsPerBar',
    );
    requireBeatUnit(song.beatUnit, 'Song.beatUnit');
    requireMinimum(
      value: song.countInBars,
      minimum: minimumCountInBars,
      label: 'Song.countInBars',
    );
    requireMinimum(
      value: song.endBar,
      minimum: minimumEndBar,
      label: 'Song.endBar',
    );

    for (final tempoChange in song.tempoChanges) {
      requireInRange(
        value: tempoChange.barIndex,
        minimum: minimumBarIndex,
        maximum: song.endBar,
        label: 'SongTempoChange.barIndex',
      );
      requireInRange(
        value: tempoChange.bpm,
        minimum: minimumBpm,
        maximum: maximumBpm,
        label: 'SongTempoChange.bpm',
      );
      requireInRange(
        value: tempoChange.beatsPerBar,
        minimum: minimumBeatsPerBar,
        maximum: maximumBeatsPerBar,
        label: 'SongTempoChange.beatsPerBar',
      );
      requireBeatUnit(tempoChange.beatUnit, 'SongTempoChange.beatUnit');
    }

    for (final loop in song.loops) {
      requireInRange(
        value: loop.startBar,
        minimum: minimumBarIndex,
        maximum: song.endBar,
        label: 'SongLoop.startBar',
      );
      requireInRange(
        value: loop.endBar,
        minimum: minimumBarIndex,
        maximum: song.endBar,
        label: 'SongLoop.endBar',
      );
      if (loop.startBar > loop.endBar) {
        throw ArgumentError.value(
          loop.startBar,
          'SongLoop.startBar',
          'SongLoop.startBar must be less than or equal to SongLoop.endBar.',
        );
      }
      requireMinimum(
        value: loop.repeatCount,
        minimum: minimumRepeatCount,
        label: 'SongLoop.repeatCount',
      );
      _validateAlternativeEndings(song, loop);
    }
    _validateLoopOverlaps(song.loops);

    for (final event in song.songEvents) {
      requireInRange(
        value: event.barIndex,
        minimum: minimumBarIndex,
        maximum: song.endBar,
        label: 'SongEvent.barIndex',
      );
      requireMinimum(
        value: event.audioCueBarsBefore,
        minimum: minimumAudioCueBarsBefore,
        label: 'SongEvent.audioCueBarsBefore',
      );

      final audioCue = event.audioCue;
      if (audioCue != null) {
        _validateAudioCue(audioCue);
      }
    }

    for (final pattern in song.beatPatterns) {
      requireInRange(
        value: pattern.barIndex,
        minimum: minimumBarIndex,
        maximum: song.endBar,
        label: 'SongBarBeatPattern.barIndex',
      );
      if (pattern.repeatPass != null) {
        requireMinimum(
          value: pattern.repeatPass!,
          minimum: minimumRepeatCount,
          label: 'SongBarBeatPattern.repeatPass',
        );
      }
      final beatsPerBarAtPattern = _beatsPerBarAtBar(song, pattern.barIndex);
      if (pattern.accents.length > beatsPerBarAtPattern) {
        throw ArgumentError.value(
          pattern.accents.length,
          'SongBarBeatPattern.accents',
          'SongBarBeatPattern.accents must not exceed beats per bar at bar '
          '${pattern.barIndex}.',
        );
      }
    }

    final linkedAudio = song.linkedAudio;
    if (linkedAudio != null) {
      _validateLinkedAudio(linkedAudio);
    }
  }

  int _beatsPerBarAtBar(Song song, int barIndex) {
    var beatsPerBar = song.beatsPerBar;
    final sortedTempoChanges = List.of(song.tempoChanges)
      ..sort((left, right) => left.barIndex.compareTo(right.barIndex));

    for (final tempoChange in sortedTempoChanges) {
      if (tempoChange.barIndex > barIndex) {
        break;
      }
      beatsPerBar = tempoChange.beatsPerBar;
    }

    return beatsPerBar;
  }

  void _validateLoopOverlaps(List<SongLoop> loops) {
    final sortedLoops = List.of(loops)
      ..sort((left, right) => left.startBar.compareTo(right.startBar));

    for (var index = 1; index < sortedLoops.length; index++) {
      final previous = sortedLoops[index - 1];
      final current = sortedLoops[index];
      if (current.startBar <= previous.endBar) {
        throw ArgumentError(
          'Song loops must not overlap: '
          '${previous.id} (${previous.startBar}-${previous.endBar}) and '
          '${current.id} (${current.startBar}-${current.endBar}).',
        );
      }
    }
  }

  void _validateAlternativeEndings(Song song, SongLoop loop) {
    final seenRepeatPasses = <int>{};
    for (final alternativeEnding in loop.alternativeEndings) {
      requireInRange(
        value: alternativeEnding.repeatPass,
        minimum: minimumRepeatCount,
        maximum: loop.repeatCount + 1,
        label: 'SongLoopAlternativeEnding.repeatPass',
      );
      if (!seenRepeatPasses.add(alternativeEnding.repeatPass)) {
        throw ArgumentError(
          'SongLoopAlternativeEnding.repeatPass must be unique per loop.',
        );
      }
      requireMinimum(
        value: alternativeEnding.lengthBars,
        minimum: minimumAlternativeEndingLengthBars,
        label: 'SongLoopAlternativeEnding.lengthBars',
      );

      for (final tempoChange in alternativeEnding.tempoChanges) {
        requireInRange(
          value: tempoChange.barIndex,
          minimum: minimumBarIndex,
          maximum: alternativeEnding.lengthBars,
          label: 'SongLoopAlternativeEnding.tempoChanges.barIndex',
        );
        requireInRange(
          value: tempoChange.bpm,
          minimum: minimumBpm,
          maximum: maximumBpm,
          label: 'SongLoopAlternativeEnding.tempoChanges.bpm',
        );
        requireInRange(
          value: tempoChange.beatsPerBar,
          minimum: minimumBeatsPerBar,
          maximum: maximumBeatsPerBar,
          label: 'SongLoopAlternativeEnding.tempoChanges.beatsPerBar',
        );
        requireBeatUnit(
          tempoChange.beatUnit,
          'SongLoopAlternativeEnding.tempoChanges.beatUnit',
        );
      }

      for (final songEvent in alternativeEnding.songEvents) {
        requireInRange(
          value: songEvent.barIndex,
          minimum: minimumBarIndex,
          maximum: alternativeEnding.lengthBars,
          label: 'SongLoopAlternativeEnding.songEvents.barIndex',
        );
        requireMinimum(
          value: songEvent.audioCueBarsBefore,
          minimum: minimumAudioCueBarsBefore,
          label: 'SongLoopAlternativeEnding.songEvents.audioCueBarsBefore',
        );
        if (songEvent.audioCue != null) {
          _validateAudioCue(songEvent.audioCue!);
        }
      }

      for (final beatPattern in alternativeEnding.beatPatterns) {
        requireInRange(
          value: beatPattern.barIndex,
          minimum: minimumBarIndex,
          maximum: alternativeEnding.lengthBars,
          label: 'SongLoopAlternativeEnding.beatPatterns.barIndex',
        );
      }
    }
  }

  void _validateAudioCue(AudioCue audioCue) {
    requireInRange(
      value: audioCue.volumePercent,
      minimum: minimumVolumePercent,
      maximum: maximumVolumePercent,
      label: 'AudioCue.volumePercent',
    );

    switch (audioCue.type) {
      case AudioCueType.voice:
        requireText(
          value: audioCue.voiceText,
          label: 'AudioCue.voiceText',
          message: 'voice cues require voice text.',
        );
      case AudioCueType.customFile:
        requireText(
          value: audioCue.customFilePath,
          label: 'AudioCue.customFilePath',
          message: 'custom file cues require a file path.',
        );
      case AudioCueType.intervalSignal:
      case AudioCueType.maxSignal:
      case AudioCueType.lowPulse:
      case AudioCueType.midPulse:
      case AudioCueType.highPulse:
        break;
    }
  }

  void _validateLinkedAudio(LinkedAudioFile linkedAudio) {
    requireText(
      value: linkedAudio.filePath,
      label: 'LinkedAudioFile.filePath',
      message: 'Linked audio requires a file path.',
    );
    requireText(
      value: linkedAudio.displayName,
      label: 'LinkedAudioFile.displayName',
      message: 'Linked audio requires a display name.',
    );
    requireMinimum(
      value: linkedAudio.offsetMilliseconds,
      minimum: minimumLinkedAudioOffsetMilliseconds,
      label: 'LinkedAudioFile.offsetMilliseconds',
    );
    requireInRange(
      value: linkedAudio.volumePercent,
      minimum: minimumVolumePercent,
      maximum: maximumVolumePercent,
      label: 'LinkedAudioFile.volumePercent',
    );
  }

}
