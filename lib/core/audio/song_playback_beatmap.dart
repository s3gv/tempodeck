import '../domain/accent_level.dart';
import '../domain/song.dart';
import '../domain/song_beatmap.dart';
import '../domain/subdivision.dart';

class SongPlaybackBeatmapBuilder {
  const SongPlaybackBeatmapBuilder();

  SongBeatmap build(Song song) {
    final entries = <SongBeatmapEntry>[];
    var playbackBarIndex = 1;
    var nextNotationBarIndex = 1;
    _PlaybackConfig? carryConfig;

    final sortedLoops = List<SongLoop>.of(song.loops)
      ..sort((left, right) => left.startBar.compareTo(right.startBar));

    for (var countInBar = song.countInBars; countInBar >= 1; countInBar -= 1) {
      final barOneConfig = _rootConfigAtBar(song, 1, 1);
      entries.add(
        SongBeatmapEntry(
          playbackBarIndex: playbackBarIndex,
          barLabel: '-$countInBar',
          barKind: SongBeatmapBarKind.countIn,
          repeatPass: 1,
          notationBarIndex: null,
          loopId: null,
          alternativeEndingId: null,
          alternativeEndingBarIndex: null,
          bpm: barOneConfig.bpm,
          beatsPerBar: barOneConfig.beatsPerBar,
          beatUnit: barOneConfig.beatUnit,
          subdivision: barOneConfig.subdivision,
          accentPattern: barOneConfig.accentPattern,
          events: const [],
          audioCueTriggers: const [],
        ),
      );
      playbackBarIndex += 1;
    }

    for (var loopIndex = 0; loopIndex < sortedLoops.length; loopIndex += 1) {
      final loop = sortedLoops[loopIndex];
      for (var notationBarIndex = nextNotationBarIndex;
          notationBarIndex < loop.startBar;
          notationBarIndex += 1) {
        final entry = _notationEntry(
          song: song,
          notationBarIndex: notationBarIndex,
          repeatPass: 1,
          playbackBarIndex: playbackBarIndex,
          carryConfig: carryConfig,
        );
        entries.add(entry.entry);
        playbackBarIndex += 1;
        carryConfig = entry.playbackConfig;
      }

      for (var repeatPass = 1; repeatPass <= loop.repeatCount + 1; repeatPass += 1) {
        var passConfig = _rootConfigAtBar(song, loop.startBar, repeatPass);
        for (var notationBarIndex = loop.startBar;
            notationBarIndex <= loop.endBar;
            notationBarIndex += 1) {
          final entry = _notationEntry(
            song: song,
            notationBarIndex: notationBarIndex,
            repeatPass: repeatPass,
            playbackBarIndex: playbackBarIndex,
            carryConfig: passConfig,
          );
          entries.add(entry.entry);
          playbackBarIndex += 1;
          passConfig = entry.playbackConfig;
        }

        final alternativeEnding = _alternativeEndingForPass(loop, repeatPass);
        if (alternativeEnding != null) {
          for (var endingBarIndex = 1;
              endingBarIndex <= alternativeEnding.lengthBars;
              endingBarIndex += 1) {
            final endingEntry = _alternativeEndingEntry(
              song: song,
              loopIndex: loopIndex + 1,
              loop: loop,
              alternativeEnding: alternativeEnding,
              endingBarIndex: endingBarIndex,
              repeatPass: repeatPass,
              playbackBarIndex: playbackBarIndex,
              carryConfig: passConfig,
            );
            entries.add(endingEntry.entry);
            playbackBarIndex += 1;
            passConfig = endingEntry.playbackConfig;
          }
        }

        if (repeatPass == loop.repeatCount + 1) {
          carryConfig = passConfig;
        }
      }

      nextNotationBarIndex = loop.endBar + 1;
    }

    for (var notationBarIndex = nextNotationBarIndex;
        notationBarIndex <= song.endBar;
        notationBarIndex += 1) {
      final entry = _notationEntry(
        song: song,
        notationBarIndex: notationBarIndex,
        repeatPass: 1,
        playbackBarIndex: playbackBarIndex,
        carryConfig: carryConfig,
      );
      entries.add(entry.entry);
      playbackBarIndex += 1;
      carryConfig = entry.playbackConfig;
    }

    return SongBeatmap(
      entries: _attachAudioCueTriggers(song, entries),
    );
  }

  _BuiltBeatmapEntry _notationEntry({
    required Song song,
    required int notationBarIndex,
    required int repeatPass,
    required int playbackBarIndex,
    required _PlaybackConfig? carryConfig,
  }) {
    final rootConfig = _rootConfigAtBar(song, notationBarIndex, repeatPass);
    final hasTempoChange = song.tempoChanges.any(
      (change) => change.barIndex == notationBarIndex,
    );
    final effectiveConfig = hasTempoChange || carryConfig == null
        ? rootConfig
        : _PlaybackConfig(
            bpm: carryConfig.bpm,
            beatsPerBar: carryConfig.beatsPerBar,
            beatUnit: carryConfig.beatUnit,
            subdivision: rootConfig.subdivision,
            accentPattern: rootConfig.accentPattern,
          );

    return _BuiltBeatmapEntry(
      entry: SongBeatmapEntry(
        playbackBarIndex: playbackBarIndex,
        barLabel: repeatPass == 1
            ? '$notationBarIndex'
            : '$notationBarIndex.$repeatPass',
        barKind: SongBeatmapBarKind.notation,
        repeatPass: repeatPass,
        notationBarIndex: notationBarIndex,
        loopId: null,
        alternativeEndingId: null,
        alternativeEndingBarIndex: null,
        bpm: effectiveConfig.bpm,
        beatsPerBar: effectiveConfig.beatsPerBar,
        beatUnit: effectiveConfig.beatUnit,
        subdivision: effectiveConfig.subdivision,
        accentPattern: effectiveConfig.accentPattern,
        events: _rootEventsAtBar(song, notationBarIndex, repeatPass),
        audioCueTriggers: const [],
      ),
      playbackConfig: effectiveConfig,
    );
  }

  _BuiltBeatmapEntry _alternativeEndingEntry({
    required Song song,
    required int loopIndex,
    required SongLoop loop,
    required SongLoopAlternativeEnding alternativeEnding,
    required int endingBarIndex,
    required int repeatPass,
    required int playbackBarIndex,
    required _PlaybackConfig carryConfig,
  }) {
    final tempoChange = alternativeEnding.tempoChanges
        .where((change) => change.barIndex == endingBarIndex)
        .cast<SongTempoChange?>()
        .firstWhere((_) => true, orElse: () => null);
    final beatPattern = _alternativeEndingBeatPattern(
      alternativeEnding,
      endingBarIndex,
      carryConfig.beatsPerBar,
    );
    final effectiveConfig = tempoChange == null
        ? _PlaybackConfig(
            bpm: carryConfig.bpm,
            beatsPerBar: carryConfig.beatsPerBar,
            beatUnit: carryConfig.beatUnit,
            subdivision: beatPattern.subdivision,
            accentPattern: beatPattern.accents,
          )
        : _PlaybackConfig(
            bpm: tempoChange.bpm,
            beatsPerBar: tempoChange.beatsPerBar,
            beatUnit: tempoChange.beatUnit,
            subdivision: beatPattern.subdivision,
            accentPattern: beatPattern.accents,
          );

    final label = '$loopIndex.$endingBarIndex.$repeatPass';

    return _BuiltBeatmapEntry(
      entry: SongBeatmapEntry(
        playbackBarIndex: playbackBarIndex,
        barLabel: label,
        barKind: SongBeatmapBarKind.alternativeEnding,
        repeatPass: repeatPass,
        notationBarIndex: loop.endBar,
        loopId: loop.id,
        alternativeEndingId: alternativeEnding.id,
        alternativeEndingBarIndex: endingBarIndex,
        bpm: effectiveConfig.bpm,
        beatsPerBar: effectiveConfig.beatsPerBar,
        beatUnit: effectiveConfig.beatUnit,
        subdivision: effectiveConfig.subdivision,
        accentPattern: effectiveConfig.accentPattern,
        events: _alternativeEndingEvents(
          alternativeEnding,
          endingBarIndex,
          label,
        ),
        audioCueTriggers: const [],
      ),
      playbackConfig: effectiveConfig,
    );
  }

  _PlaybackConfig _rootConfigAtBar(Song song, int notationBarIndex, int repeatPass) {
    final tempoConfig = _tempoConfigAtNotationBar(song, notationBarIndex);
    final beatPattern = _beatPatternAtNotationBar(
      song,
      notationBarIndex: notationBarIndex,
      repeatPass: repeatPass,
      beatsPerBar: tempoConfig.beatsPerBar,
    );
    return _PlaybackConfig(
      bpm: tempoConfig.bpm,
      beatsPerBar: tempoConfig.beatsPerBar,
      beatUnit: tempoConfig.beatUnit,
      subdivision: beatPattern.subdivision,
      accentPattern: List<AccentLevel>.unmodifiable(beatPattern.accents),
    );
  }

  _TempoConfig _tempoConfigAtNotationBar(Song song, int notationBarIndex) {
    final sortedTempoChanges = List<SongTempoChange>.of(song.tempoChanges)
      ..sort((left, right) => left.barIndex.compareTo(right.barIndex));

    var bpm = song.startBpm;
    var beatsPerBar = song.beatsPerBar;
    var beatUnit = song.beatUnit;
    for (final tempoChange in sortedTempoChanges) {
      if (tempoChange.barIndex > notationBarIndex) {
        break;
      }
      bpm = tempoChange.bpm;
      beatsPerBar = tempoChange.beatsPerBar;
      beatUnit = tempoChange.beatUnit;
    }

    return _TempoConfig(
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
    );
  }

  _BeatPatternData _beatPatternAtNotationBar(
    Song song, {
    required int notationBarIndex,
    required int repeatPass,
    required int beatsPerBar,
  }) {
    SongBarBeatPattern? genericPattern;
    SongBarBeatPattern? specificPattern;
    for (final pattern in song.beatPatterns) {
      if (pattern.barIndex != notationBarIndex) {
        continue;
      }
      if (pattern.repeatPass == repeatPass) {
        specificPattern = pattern;
      } else if (pattern.repeatPass == null) {
        genericPattern = pattern;
      }
    }

    final pattern = specificPattern ?? genericPattern;
    if (pattern == null) {
      return _BeatPatternData(
        accents: _defaultAccents(beatsPerBar),
        subdivision: Subdivision.one,
      );
    }

    return _BeatPatternData(
      accents: List<AccentLevel>.unmodifiable(pattern.accents),
      subdivision: pattern.subdivision,
    );
  }

  SongLoopAlternativeEnding? _alternativeEndingForPass(
    SongLoop loop,
    int repeatPass,
  ) {
    for (final alternativeEnding in loop.alternativeEndings) {
      if (alternativeEnding.repeatPass == repeatPass) {
        return alternativeEnding;
      }
    }
    return null;
  }

  _BeatPatternData _alternativeEndingBeatPattern(
    SongLoopAlternativeEnding alternativeEnding,
    int endingBarIndex,
    int beatsPerBar,
  ) {
    final pattern = alternativeEnding.beatPatterns
        .where((item) => item.barIndex == endingBarIndex)
        .cast<SongBarBeatPattern?>()
        .firstWhere((_) => true, orElse: () => null);
    if (pattern == null) {
      return _BeatPatternData(
        accents: _defaultAccents(beatsPerBar),
        subdivision: Subdivision.one,
      );
    }

    return _BeatPatternData(
      accents: List<AccentLevel>.unmodifiable(pattern.accents),
      subdivision: pattern.subdivision,
    );
  }

  List<AccentLevel> _defaultAccents(int beatsPerBar) {
    if (beatsPerBar <= 0) {
      return const <AccentLevel>[AccentLevel.high];
    }

    return List<AccentLevel>.generate(
      beatsPerBar,
      (index) => index == 0 ? AccentLevel.high : AccentLevel.normal,
      growable: false,
    );
  }

  List<SongBeatmapEvent> _rootEventsAtBar(
    Song song,
    int notationBarIndex,
    int repeatPass,
  ) {
    final barLabel = repeatPass == 1
        ? '$notationBarIndex'
        : '$notationBarIndex.$repeatPass';
    final events = <SongBeatmapEvent>[];

    for (final change in song.tempoChanges.where((item) => item.barIndex == notationBarIndex)) {
      events.add(
        SongBeatmapEvent(
          id: change.id,
          kind: SongBeatmapEventKind.tempoChange,
          label: 'Tempo -> ${change.bpm} BPM (${change.beatsPerBar}/${change.beatUnit})',
          barLabel: barLabel,
          bpm: change.bpm,
          beatsPerBar: change.beatsPerBar,
          beatUnit: change.beatUnit,
          sourceBarIndex: change.barIndex,
        ),
      );
    }

    for (final loop in song.loops.where((item) => item.startBar == notationBarIndex)) {
      events.add(
        SongBeatmapEvent(
          id: loop.id,
          kind: SongBeatmapEventKind.loopStart,
          label: 'Loop start ($repeatPass/${loop.repeatCount + 1})',
          barLabel: barLabel,
          loopStartBar: loop.startBar,
          loopEndBar: loop.endBar,
          loopIteration: repeatPass,
          loopTotalIterations: loop.repeatCount + 1,
          sourceBarIndex: loop.startBar,
        ),
      );
    }

    for (final loop in song.loops.where((item) => item.endBar == notationBarIndex)) {
      events.add(
        SongBeatmapEvent(
          id: loop.id,
          kind: SongBeatmapEventKind.loopEnd,
          label: 'Loop end ($repeatPass/${loop.repeatCount + 1})',
          barLabel: barLabel,
          loopStartBar: loop.startBar,
          loopEndBar: loop.endBar,
          loopIteration: repeatPass,
          loopTotalIterations: loop.repeatCount + 1,
          sourceBarIndex: loop.endBar,
        ),
      );
    }

    for (final event in song.songEvents.where((item) => item.barIndex == notationBarIndex)) {
      events.add(
        SongBeatmapEvent(
          id: event.id,
          kind: SongBeatmapEventKind.songMarker,
          label: event.label,
          barLabel: barLabel,
          sourceBarIndex: event.barIndex,
        ),
      );
    }

    return List<SongBeatmapEvent>.unmodifiable(events);
  }

  List<SongBeatmapEvent> _alternativeEndingEvents(
    SongLoopAlternativeEnding alternativeEnding,
    int endingBarIndex,
    String barLabel,
  ) {
    final events = <SongBeatmapEvent>[];
    for (final change
        in alternativeEnding.tempoChanges.where((item) => item.barIndex == endingBarIndex)) {
      events.add(
        SongBeatmapEvent(
          id: change.id,
          kind: SongBeatmapEventKind.tempoChange,
          label: 'Tempo -> ${change.bpm} BPM (${change.beatsPerBar}/${change.beatUnit})',
          barLabel: barLabel,
          bpm: change.bpm,
          beatsPerBar: change.beatsPerBar,
          beatUnit: change.beatUnit,
          sourceBarIndex: change.barIndex,
        ),
      );
    }

    for (final event
        in alternativeEnding.songEvents.where((item) => item.barIndex == endingBarIndex)) {
      events.add(
        SongBeatmapEvent(
          id: event.id,
          kind: SongBeatmapEventKind.songMarker,
          label: event.label,
          barLabel: barLabel,
          sourceBarIndex: event.barIndex,
        ),
      );
    }

    return List<SongBeatmapEvent>.unmodifiable(events);
  }

  List<SongBeatmapEntry> _attachAudioCueTriggers(
    Song song,
    List<SongBeatmapEntry> entries,
  ) {
    final cueTriggersByPlaybackBar = <int, List<SongBeatmapAudioCueTrigger>>{};

    for (final sourceEvent in song.songEvents.where((event) => event.audioCue != null)) {
      _attachCueTriggersForRootEvent(
        entries: entries,
        songEvent: sourceEvent,
        cueTriggersByPlaybackBar: cueTriggersByPlaybackBar,
      );
    }

    for (final loop in song.loops) {
      for (final alternativeEnding in loop.alternativeEndings) {
        for (final sourceEvent
            in alternativeEnding.songEvents.where((event) => event.audioCue != null)) {
          _attachCueTriggersForAlternativeEndingEvent(
            entries: entries,
            loop: loop,
            alternativeEnding: alternativeEnding,
            songEvent: sourceEvent,
            cueTriggersByPlaybackBar: cueTriggersByPlaybackBar,
          );
        }
      }
    }

    return [
      for (final entry in entries)
        SongBeatmapEntry(
          playbackBarIndex: entry.playbackBarIndex,
          barLabel: entry.barLabel,
          barKind: entry.barKind,
          repeatPass: entry.repeatPass,
          notationBarIndex: entry.notationBarIndex,
          loopId: entry.loopId,
          alternativeEndingId: entry.alternativeEndingId,
          alternativeEndingBarIndex: entry.alternativeEndingBarIndex,
          bpm: entry.bpm,
          beatsPerBar: entry.beatsPerBar,
          beatUnit: entry.beatUnit,
          subdivision: entry.subdivision,
          accentPattern: entry.accentPattern,
          events: entry.events,
          audioCueTriggers: List.unmodifiable(
            cueTriggersByPlaybackBar[entry.playbackBarIndex] ?? const [],
          ),
        ),
    ];
  }

  void _attachCueTriggersForRootEvent({
    required List<SongBeatmapEntry> entries,
    required SongEvent songEvent,
    required Map<int, List<SongBeatmapAudioCueTrigger>> cueTriggersByPlaybackBar,
  }) {
    final targetEntries = entries
        .where(
          (entry) =>
              entry.notationBarIndex == songEvent.barIndex &&
              entry.barKind == SongBeatmapBarKind.notation,
        )
        .toList(growable: false);

    for (final targetEntry in targetEntries) {
      _attachCueTrigger(
        entries: entries,
        targetPlaybackBarIndex: targetEntry.playbackBarIndex,
        sourceBarLabel: targetEntry.barLabel,
        songEvent: songEvent,
        cueTriggersByPlaybackBar: cueTriggersByPlaybackBar,
      );
    }
  }

  void _attachCueTriggersForAlternativeEndingEvent({
    required List<SongBeatmapEntry> entries,
    required SongLoop loop,
    required SongLoopAlternativeEnding alternativeEnding,
    required SongEvent songEvent,
    required Map<int, List<SongBeatmapAudioCueTrigger>> cueTriggersByPlaybackBar,
  }) {
    final targetEntries = entries
        .where(
          (entry) =>
              entry.loopId == loop.id &&
              entry.alternativeEndingId == alternativeEnding.id &&
              entry.alternativeEndingBarIndex == songEvent.barIndex,
        )
        .toList(growable: false);

    for (final targetEntry in targetEntries) {
      _attachCueTrigger(
        entries: entries,
        targetPlaybackBarIndex: targetEntry.playbackBarIndex,
        sourceBarLabel: targetEntry.barLabel,
        songEvent: songEvent,
        cueTriggersByPlaybackBar: cueTriggersByPlaybackBar,
      );
    }
  }

  void _attachCueTrigger({
    required List<SongBeatmapEntry> entries,
    required int targetPlaybackBarIndex,
    required String sourceBarLabel,
    required SongEvent songEvent,
    required Map<int, List<SongBeatmapAudioCueTrigger>> cueTriggersByPlaybackBar,
  }) {
    final audioCue = songEvent.audioCue;
    if (audioCue == null) {
      return;
    }

    final triggerPlaybackBarIndex = targetPlaybackBarIndex - songEvent.audioCueBarsBefore;
    if (triggerPlaybackBarIndex < 1 || triggerPlaybackBarIndex > entries.length) {
      return;
    }

    final triggers = cueTriggersByPlaybackBar.putIfAbsent(
      triggerPlaybackBarIndex,
      () => <SongBeatmapAudioCueTrigger>[],
    );
    triggers.add(
      SongBeatmapAudioCueTrigger(
        sourceEventId: songEvent.id,
        sourceBarLabel: sourceBarLabel,
        label: songEvent.label,
        audioCue: audioCue,
      ),
    );
  }
}

class _TempoConfig {
  const _TempoConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
  });

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
}

class _PlaybackConfig {
  const _PlaybackConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.accentPattern,
  });

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final List<AccentLevel> accentPattern;
}

class _BeatPatternData {
  const _BeatPatternData({
    required this.accents,
    required this.subdivision,
  });

  final List<AccentLevel> accents;
  final Subdivision subdivision;
}

class _BuiltBeatmapEntry {
  const _BuiltBeatmapEntry({
    required this.entry,
    required this.playbackConfig,
  });

  final SongBeatmapEntry entry;
  final _PlaybackConfig playbackConfig;
}
