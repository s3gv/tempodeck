import '../domain/click_sound_set.dart';

enum ClickSoundVariant { accentHigh, accentLow, normal, subdivision }

class ClickSoundSetAssets {
  const ClickSoundSetAssets._({
    required this.accentHigh,
    required this.accentLow,
    required this.normal,
    required this.subdivision,
  });

  final String accentHigh;
  final String accentLow;
  final String normal;
  final String subdivision;

  Iterable<String> get assetPaths => ClickSoundVariant.values.map(assetPathFor);

  String assetPathFor(ClickSoundVariant variant) {
    return switch (variant) {
      ClickSoundVariant.accentHigh => accentHigh,
      ClickSoundVariant.accentLow => accentLow,
      ClickSoundVariant.normal => normal,
      ClickSoundVariant.subdivision => subdivision,
    };
  }

  static ClickSoundSetAssets forSoundSet(ClickSoundSet soundSet) {
    final slug = switch (soundSet) {
      ClickSoundSet.tock => 'tock',
      ClickSoundSet.blip => 'blip',
      ClickSoundSet.drumKit => 'drum_kit',
      ClickSoundSet.hype => 'hype',
      ClickSoundSet.metalKit => 'metal_kit',
      ClickSoundSet.mightyKit => 'mighty_kit',
    };

    return ClickSoundSetAssets._(
      accentHigh: 'assets/audio/click_kits/$slug/${slug}_accent_high.wav',
      accentLow: 'assets/audio/click_kits/$slug/${slug}_accent_low.wav',
      normal: 'assets/audio/click_kits/$slug/${slug}_normal.wav',
      subdivision: 'assets/audio/click_kits/$slug/${slug}_subdivision.wav',
    );
  }
}
