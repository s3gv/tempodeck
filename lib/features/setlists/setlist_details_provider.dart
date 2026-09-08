import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/setlist.dart';
import '../../core/providers/repository_providers.dart';

final setlistDetailsProvider = StreamProvider.family<Setlist?, String>(
  (ref, setlistId) => ref.watch(setlistRepositoryProvider).watchSetlistById(setlistId),
);
