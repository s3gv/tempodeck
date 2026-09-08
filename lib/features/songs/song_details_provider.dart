import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/song.dart';
import '../../core/providers/repository_providers.dart';

final songDetailsProvider = StreamProvider.family<Song?, String>(
  (ref, songId) => ref.watch(songRepositoryProvider).watchSongById(songId),
);
