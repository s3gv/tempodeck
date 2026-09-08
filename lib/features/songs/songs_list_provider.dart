import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/song.dart';
import '../../core/providers/repository_providers.dart';

final songsListProvider = StreamProvider<List<Song>>(
  (ref) => ref.watch(songRepositoryProvider).watchAllSongs(),
);
