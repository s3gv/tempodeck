/// Calculates the duration of one beat given BPM and beat unit.
///
/// The beat unit is the denominator of the time signature (4 = quarter note,
/// 8 = eighth note, etc.). The returned duration accounts for the beat unit
/// relative to a quarter note.
///
/// Matches the live playback formula from `MetronomeClickEngine`:
/// `(60 / bpm) * (4 / beatUnit)` seconds per beat.
Duration beatDuration({
  required int bpm,
  required int beatUnit,
}) {
  const quarterNotesPerWholeNote = 4;
  final quarterNoteDuration = Duration.microsecondsPerMinute / bpm;
  final beatDurationMicros =
      quarterNoteDuration * (quarterNotesPerWholeNote / beatUnit);
  return Duration(microseconds: beatDurationMicros.round());
}
