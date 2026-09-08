import 'dart:convert';

import '../domain/audio_cue.dart';
import '../domain/interval_settings.dart';
import '../domain/linked_audio_file.dart';
import '../domain/metronome_preset.dart';
import '../domain/setlist.dart';
import '../domain/song.dart';
import '../repositories/preset_repository.dart';
import '../repositories/setlist_repository.dart';
import '../repositories/song_repository.dart';

class JsonBackupExporter {
  const JsonBackupExporter({
    required SongRepository songRepository,
    required SetlistRepository setlistRepository,
    required PresetRepository presetRepository,
    DateTime Function()? now,
  })  : _songRepository = songRepository,
        _setlistRepository = setlistRepository,
        _presetRepository = presetRepository,
        _now = now ?? DateTime.now;

  static const int schemaVersion = 1;

  final SongRepository _songRepository;
  final SetlistRepository _setlistRepository;
  final PresetRepository _presetRepository;
  final DateTime Function() _now;

  Future<String> exportJson() async {
    final songs = await _songRepository.getAllSongs();
    final setlists = await _setlistRepository.getAllSetlists();
    final presets = await _presetRepository.getAllPresets();

    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'exportedAt': _now().toUtc().toIso8601String(),
      'songs': songs.map(_encodeSong).toList(growable: false),
      'setlists': setlists.map(_encodeSetlist).toList(growable: false),
      'presets': presets.map(_encodePreset).toList(growable: false),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, Object?> _encodeSong(Song song) {
    return <String, Object?>{
      'id': song.id,
      'title': song.title,
      'createdAt': song.createdAt.toUtc().toIso8601String(),
      'startBpm': song.startBpm,
      'beatsPerBar': song.beatsPerBar,
      'beatUnit': song.beatUnit,
      'countInBars': song.countInBars,
      'endBar': song.endBar,
      'tempoChanges': song.tempoChanges.map(_encodeTempoChange).toList(
            growable: false,
          ),
      'loops': song.loops.map(_encodeLoop).toList(growable: false),
      'songEvents': song.songEvents.map(_encodeSongEvent).toList(
            growable: false,
          ),
      'beatPatterns': song.beatPatterns.map(_encodeBeatPattern).toList(
            growable: false,
          ),
      'linkedAudio': song.linkedAudio == null
          ? null
          : _encodeLinkedAudio(song.linkedAudio!),
    };
  }

  Map<String, Object?> _encodeTempoChange(SongTempoChange tempoChange) {
    return <String, Object?>{
      'id': tempoChange.id,
      'barIndex': tempoChange.barIndex,
      'bpm': tempoChange.bpm,
      'beatsPerBar': tempoChange.beatsPerBar,
      'beatUnit': tempoChange.beatUnit,
    };
  }

  Map<String, Object?> _encodeLoop(SongLoop loop) {
    return <String, Object?>{
      'id': loop.id,
      'startBar': loop.startBar,
      'endBar': loop.endBar,
      'repeatCount': loop.repeatCount,
    };
  }

  Map<String, Object?> _encodeSongEvent(SongEvent event) {
    return <String, Object?>{
      'id': event.id,
      'barIndex': event.barIndex,
      'label': event.label,
      'audioCue':
          event.audioCue == null ? null : _encodeAudioCue(event.audioCue!),
      'audioCueBarsBefore': event.audioCueBarsBefore,
    };
  }

  Map<String, Object?> _encodeBeatPattern(SongBarBeatPattern beatPattern) {
    return <String, Object?>{
      'id': beatPattern.id,
      'barIndex': beatPattern.barIndex,
      'accents': beatPattern.accents
          .map((accentLevel) => accentLevel.name)
          .toList(growable: false),
      'subdivision': beatPattern.subdivision.name,
      'repeatPass': beatPattern.repeatPass,
    };
  }

  Map<String, Object?> _encodeSetlist(Setlist setlist) {
    return <String, Object?>{
      'id': setlist.id,
      'title': setlist.title,
      'createdAt': setlist.createdAt.toUtc().toIso8601String(),
      'items': setlist.items.map(_encodeSetlistItem).toList(growable: false),
    };
  }

  Map<String, Object?> _encodeSetlistItem(SetlistItem item) {
    return <String, Object?>{
      'id': item.id,
      'songId': item.songId,
      'songTitle': item.songTitle,
      'playbackEnabled': item.playbackEnabled,
      'playAttachedAudio': item.playAttachedAudio,
      'transitionSteps': item.transitionSteps.map(_encodeTransitionStep).toList(
            growable: false,
          ),
    };
  }

  Map<String, Object?> _encodeTransitionStep(SetlistTransitionStep step) {
    return <String, Object?>{
      'id': step.id,
      'type': step.type.name,
      'value': step.value,
      'audioCue':
          step.audioCue == null ? null : _encodeAudioCue(step.audioCue!),
    };
  }

  Map<String, Object?> _encodePreset(MetronomePreset preset) {
    return <String, Object?>{
      'id': preset.id,
      'name': preset.name,
      'bpm': preset.bpm,
      'beatsPerBar': preset.beatsPerBar,
      'beatUnit': preset.beatUnit,
      'subdivision': preset.subdivision.name,
      'clickSoundSet': preset.clickSoundSet.name,
      'masterVolumePercent': preset.masterVolumePercent,
      'accentPattern': preset.accentPattern
          .map((accentLevel) => accentLevel.name)
          .toList(growable: false),
      'intervalSettings': preset.intervalSettings == null
          ? null
          : _encodeIntervalSettings(preset.intervalSettings!),
    };
  }

  Map<String, Object?> _encodeIntervalSettings(
    IntervalSettings intervalSettings,
  ) {
    return <String, Object?>{
      'intervalMillis': intervalSettings.interval.inMilliseconds,
      'bpmStepEnabled': intervalSettings.bpmStepEnabled,
      'bpmStep': intervalSettings.bpmStep,
      'maxDurationMillis': intervalSettings.maxDuration?.inMilliseconds,
    };
  }

  Map<String, Object?> _encodeLinkedAudio(LinkedAudioFile linkedAudio) {
    return <String, Object?>{
      'filePath': linkedAudio.filePath,
      'displayName': linkedAudio.displayName,
      'bookmarkBase64': null,
      'offsetMillis': linkedAudio.offsetMilliseconds,
      'playInLiveMode': linkedAudio.playInLiveMode,
      'volumePercent': linkedAudio.volumePercent,
    };
  }

  Map<String, Object?> _encodeAudioCue(AudioCue audioCue) {
    return <String, Object?>{
      'type': audioCue.type.name,
      'voiceText': audioCue.voiceText,
      'voiceIdentifier': audioCue.voiceIdentifier,
      'customFilePath': audioCue.customFilePath,
      'customFileDisplayName': audioCue.customFileDisplayName,
      'customFileBookmarkBase64': null,
      'volumePercent': audioCue.volumePercent,
    };
  }
}
