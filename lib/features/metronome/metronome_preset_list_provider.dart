import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/metronome_preset.dart';
import '../../core/providers/repository_providers.dart';

final metronomePresetListProvider = StreamProvider<List<MetronomePreset>>(
  (ref) => ref.watch(presetRepositoryProvider).watchAllPresets(),
);
