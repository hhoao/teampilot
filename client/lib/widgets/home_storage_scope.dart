import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/storage/home_storage.dart';

/// Resolves the scoped [HomeStorage] registered by the app shell
/// (`RepositoryProvider<HomeStorage>` in main.dart).
///
/// Widget-tree replacement for the deleted `AppStorage.tolerantHome` seam:
/// bare widget tests that mount a surface without the provider fall back to
/// [HomeStorage.nativeDefault] (logged once, system-temp rooted) instead of
/// throwing — production always registers the provider above
/// `MaterialApp.router`, so reaching the fallback there is a wiring bug the
/// log surfaces.
HomeStorage homeStorageOf(BuildContext context) {
  try {
    return context.read<HomeStorage>();
  } on ProviderNotFoundException {
    return HomeStorage.nativeDefault();
  }
}
