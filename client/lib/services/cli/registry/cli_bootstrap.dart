import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';

/// Marker interface for per-CLI bootstrap entries.
///
/// Each CLI directory may define a concrete entry class holding runtime services
/// (credentials, model catalogs, …) that are injected after [AppStorage] is
/// ready.
abstract interface class CliBootstrapEntry {}

/// Runtime services wired into [CliToolRegistry] after [AppStorage] is ready.
///
/// Add a new CLI: create a [CliBootstrapEntry] in the CLI directory and add it
/// to the map in [AppShell]; no changes needed here.
@immutable
class CliBootstrap {
  const CliBootstrap(this._entries);

  final Map<CliTool, CliBootstrapEntry> _entries;

  /// Returns the [CliBootstrapEntry] for [cli] cast to [T], or `null`.
  T? entry<T extends CliBootstrapEntry>(CliTool cli) {
    final e = _entries[cli];
    return e is T ? e : null;
  }
}
