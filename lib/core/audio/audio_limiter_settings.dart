class AudioLimiterSettings {
  const AudioLimiterSettings({
    this.wet = defaultWet,
    this.threshold = defaultThreshold,
    this.outputCeiling = defaultOutputCeiling,
    this.kneeWidth = defaultKneeWidth,
    this.releaseTimeMs = defaultReleaseTimeMs,
    this.attackTimeMs = defaultAttackTimeMs,
  })  : assert(
          wet >= 0 && wet <= 1,
          'Limiter wet mix must stay within 0.0–1.0.',
        ),
        assert(
          threshold >= -60 && threshold <= 0,
          'Limiter threshold must stay within -60.0–0.0 dB.',
        ),
        assert(
          outputCeiling >= -60 && outputCeiling <= 0,
          'Limiter output ceiling must stay within -60.0–0.0 dB.',
        ),
        assert(
          kneeWidth >= 0 && kneeWidth <= 30,
          'Limiter knee width must stay within 0.0–30.0 dB.',
        ),
        assert(
          releaseTimeMs >= 1 && releaseTimeMs <= 1000,
          'Limiter release time must stay within 1.0–1000.0 ms.',
        ),
        assert(
          attackTimeMs >= 0.1 && attackTimeMs <= 200,
          'Limiter attack time must stay within 0.1–200.0 ms.',
        );

  static const double defaultWet = 1.0;
  static const double defaultThreshold = -6.0;
  static const double defaultOutputCeiling = -1.0;
  static const double defaultKneeWidth = 2.0;
  static const double defaultReleaseTimeMs = 100.0;
  static const double defaultAttackTimeMs = 1.0;

  final double wet;
  final double threshold;
  final double outputCeiling;
  final double kneeWidth;
  final double releaseTimeMs;
  final double attackTimeMs;
}
