import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/storage/home_storage.dart';

/// Resolves the scoped [HomeStorage] registered by the app shell
/// (`RepositoryProvider<HomeStorage>` in main.dart).
///
/// No fallback: a mount tree without the provider is a wiring bug and must
/// fail loudly (ProviderNotFoundException), not silently read a wrong home.
HomeStorage homeStorageOf(BuildContext context) => context.read<HomeStorage>();
