import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';

final setlistsListProvider = StreamProvider(
  (ref) => ref.watch(setlistRepositoryProvider).watchAllSetlists(),
);
