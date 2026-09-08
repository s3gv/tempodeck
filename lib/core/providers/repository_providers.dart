import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../repositories/drift_preset_repository.dart';
import '../repositories/drift_setlist_repository.dart';
import '../repositories/drift_song_repository.dart';
import '../repositories/metronome_settings_repository.dart';
import '../repositories/mixer_settings_repository.dart';
import '../repositories/preset_repository.dart';
import '../repositories/setlist_repository.dart';
import '../repositories/song_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  // Use application support directory (internal, not user-visible) instead of
  // the default documents directory which is exposed via iOS Files app.
  final database = AppDatabase(
    driftDatabase(
      name: 'tempodeck',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );
  ref.onDispose(database.close);
  return database;
});

final presetRepositoryProvider = Provider<PresetRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftPresetRepository(presetDao: database.presetDao);
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftSongRepository(songDao: database.songDao);
});

final setlistRepositoryProvider = Provider<SetlistRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftSetlistRepository(setlistDao: database.setlistDao);
});

final mixerSettingsRepositoryProvider = Provider<MixerSettingsRepository>(
  (ref) => SharedPreferencesMixerSettingsRepository(),
);

final metronomeSettingsRepositoryProvider =
    Provider<MetronomeSettingsRepository>(
  (ref) => SharedPreferencesMetronomeSettingsRepository(),
);
