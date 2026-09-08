class LinkedAudioFile {
  const LinkedAudioFile({
    required this.filePath,
    required this.displayName,
    this.offsetMilliseconds = 0,
    this.volumePercent = 100,
    this.playInLiveMode = true,
  });

  final String filePath;
  final String displayName;
  final int offsetMilliseconds;
  final int volumePercent;
  final bool playInLiveMode;
}
