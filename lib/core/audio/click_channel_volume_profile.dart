import 'click_sound_set_assets.dart';

class ClickChannelVolumeProfile {
  const ClickChannelVolumeProfile({
    this.accentHigh = defaultChannelVolume,
    this.accentLow = defaultChannelVolume,
    this.normal = defaultChannelVolume,
    this.subdivision = defaultChannelVolume,
  }) : assert(
         accentHigh >= 0 && accentHigh <= 1,
         'Accent-high volume must stay within 0.0–1.0.',
       ),
       assert(
         accentLow >= 0 && accentLow <= 1,
         'Accent-low volume must stay within 0.0–1.0.',
       ),
       assert(
         normal >= 0 && normal <= 1,
         'Normal volume must stay within 0.0–1.0.',
       ),
       assert(
         subdivision >= 0 && subdivision <= 1,
         'Subdivision volume must stay within 0.0–1.0.',
       );

  static const double defaultChannelVolume = 1;

  final double accentHigh;
  final double accentLow;
  final double normal;
  final double subdivision;

  double volumeFor(ClickSoundVariant variant) {
    return switch (variant) {
      ClickSoundVariant.accentHigh => accentHigh,
      ClickSoundVariant.accentLow => accentLow,
      ClickSoundVariant.normal => normal,
      ClickSoundVariant.subdivision => subdivision,
    };
  }

  ClickChannelVolumeProfile copyWithVolume(
    ClickSoundVariant variant,
    double volume,
  ) {
    return ClickChannelVolumeProfile(
      accentHigh: variant == ClickSoundVariant.accentHigh ? volume : accentHigh,
      accentLow: variant == ClickSoundVariant.accentLow ? volume : accentLow,
      normal: variant == ClickSoundVariant.normal ? volume : normal,
      subdivision:
          variant == ClickSoundVariant.subdivision ? volume : subdivision,
    );
  }
}
