class IntervalSettings {
  const IntervalSettings({
    required this.interval,
    this.bpmStepEnabled = false,
    this.bpmStep = 5,
    this.maxDuration,
  });

  final Duration interval;
  final bool bpmStepEnabled;
  final int bpmStep;
  final Duration? maxDuration;
}
