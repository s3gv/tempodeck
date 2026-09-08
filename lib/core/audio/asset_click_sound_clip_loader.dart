import 'package:flutter/services.dart';

import '../domain/click_sound_set.dart';
import 'click_sound_set_assets.dart';
import 'click_track_export_augmenter.dart';
import 'export_audio_clip_utils.dart';
import 'export_engine.dart';
import 'wave_file_decoder.dart';

class AssetClickSoundClipLoader implements ClickSoundClipLoader {
  const AssetClickSoundClipLoader({
    WaveFileDecoder waveFileDecoder = const WaveFileDecoder(),
  }) : _waveFileDecoder = waveFileDecoder;

  final WaveFileDecoder _waveFileDecoder;

  @override
  Future<ExportAudioClip> loadClip(
    ClickSoundSet soundSet,
    ClickSoundVariant variant,
  ) async {
    final assetPath =
        ClickSoundSetAssets.forSoundSet(soundSet).assetPathFor(variant);
    final byteData = await rootBundle.load(assetPath);
    final clip = _waveFileDecoder.decode(byteData.buffer.asUint8List());
    return ensureStereo(clip);
  }
}
