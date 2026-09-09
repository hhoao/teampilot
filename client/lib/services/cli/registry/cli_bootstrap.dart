import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';
import '../../storage/home_storage.dart';

/// Marker interface for per-CLI bootstrap entries.
///
/// Each CLI directory may define a concrete entry class holding runtime services
/// (credentials, model catalogs, …) that are injected after the home storage
/// context is ready.
abstract interface class CliBootstrapEntry {}

/// Runtime services wired into [CliToolRegistry] after the home storage
/// context is ready.
///
/// Add a new CLI: create a [CliBootstrapEntry] in the CLI directory and add it
/// to the map in [AppShell]; no changes needed here.
@immutable
class CliBootstrap {
  const CliBootstrap(this._entries, {this.storage});

  final Map<CliTool, CliBootstrapEntry> _entries;

  /// Home control-plane storage threaded into capabilities (headless
  /// provisioning, provider credential actions, …) when the registry is
  /// (re-)configured. Null for the pre-bootstrap default registration, whose
  /// capabilities only serve launch-arg assembly.
  final HomeStorage? storage;

  /// Returns the [CliBootstrapEntry] for [cli] cast to [T], or `null`.
  T? entry<T extends CliBootstrapEntry>(CliTool cli) {
    final e = _entries[cli];
    return e is T ? e : null;
  }
}
