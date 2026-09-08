import '../domain/click_sound_set.dart';

sealed class ExportSource {}

enum ExportMp3Layout { singleFile, cutOnManual }

class ExportContentOptions {
  const ExportContentOptions({
    this.includeClickTrack = true,
    this.includeLinkedAudio = true,
    this.includeAudioCues = true,
    this.includeCountIn = true,
    this.clickSoundSet = ClickSoundSet.tock,
    this.metronomeVolumePercent = 80,
    this.cueVolumePercent = 80,
  });

  final bool includeClickTrack;
  final bool includeLinkedAudio;
  final bool includeAudioCues;
  final bool includeCountIn;
  final ClickSoundSet clickSoundSet;
  final int metronomeVolumePercent;
  final int cueVolumePercent;

  double get metronomeGain => metronomeVolumePercent / 100;
  double get cueGain => cueVolumePercent / 100;
}

class SongExportSource extends ExportSource {
  SongExportSource(this.songId);
  final String songId;
}

class SetlistExportSource extends ExportSource {
  SetlistExportSource(this.setlistId);
  final String setlistId;
}

abstract class IExportEngine {
  int estimateFileSizeBytes({
    required Duration duration,
    int bitrateBps = 192000,
  });

  Stream<double> exportToMp3({
    required ExportSource source,
    required String outputPath,
    int bitrateBps = 192000,
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
    void Function(List<String> warnings)? onWarnings,
  });
}
