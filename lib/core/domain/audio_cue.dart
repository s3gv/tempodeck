enum AudioCueType {
  intervalSignal,
  maxSignal,
  lowPulse,
  midPulse,
  highPulse,
  voice,
  customFile,
}

class AudioCue {
  const AudioCue({
    required this.type,
    this.voiceText,
    this.voiceIdentifier,
    this.customFilePath,
    this.customFileDisplayName,
    this.volumePercent = 100,
  });

  final AudioCueType type;
  final String? voiceText;
  final String? voiceIdentifier;
  final String? customFilePath;
  final String? customFileDisplayName;
  final int volumePercent;
}
