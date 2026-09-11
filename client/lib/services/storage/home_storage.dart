import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'app_paths.dart';
import 'runtime_context.dart';
import '../../utils/logging/logger.dart';

/// A home-plane swap: the context published so far, the context published by
/// the swap, and the generation it produced.
class StoragePlaneChange {
  const StoragePlaneChange({
    required this.oldContext,
    required this.newContext,
    required this.generation,
  });

  final RuntimeContext oldContext;
  final RuntimeContext newContext;
  final int generation;
}

/// Injected, versioned, drain-safe facade for the **home control plane**.
///
/// Replaces the runtime-mutable `AppStorage` global: the current
/// [RuntimeContext] is published here, every swap bumps [generation] and emits
/// [changes], and the outgoing context is retired only after the swap is
/// visible to new operations — the [retire] callback (wired from the app shell
/// to the runtime-context registry / SSH client factory) is drain-safe by
/// contract (Task 5: tracked in-flight ops, deferred transport close).
class HomeStorage {
  HomeStorage(RuntimeContext context, {this.retire}) : _current = context;

  /// Invoked with the outgoing context after a swap published the new one.
  /// Drains and evicts the old transport (registry dispose → SSH profile
  /// disconnect with deferred close).
  final Future<void> Function(RuntimeContext old)? retire;

  RuntimeContext _current;
  int _generation = 0;
  final _changes = StreamController<StoragePlaneChange>.broadcast();

  /// Current published context (immutable value object).
  RuntimeContext get context => _current;

  Filesystem get fs => _current.filesystem;

  AppPaths get paths => _current.paths;

  String get home => _current.home;

  /// Default workspace for new workspaces and CLI sessions (native: app Documents).
  String get cwd => _current.cwd;

  String get appDataRoot => _current.appDataRoot;

  bool get usesPosixPaths => _current.usesPosixPaths;

  /// Increments once per published swap (never on a no-op).
  int get generation => _generation;

  /// Broadcast stream of published swaps.
  Stream<StoragePlaneChange> get changes => _changes.stream;

  /// Publishes [next] as the home context.
  ///
  /// The new context becomes visible to new operations **synchronously**
  /// (before any awaiting), then [changes] fires with the old/new contexts and
  /// the new generation, and only then does the old context's [retire] drain
  /// run — in-flight operations on the old plane complete against a transport
  /// that stays alive until they finish. Swapping in the identical context is
  /// a full no-op (no emit, no generation bump, no retire).
  ///
  /// [drainTimeout] is reserved for future drain bounding; drain safety is
  /// the [retire] callback's contract (Task 5: it drains on its own).
  Future<void> swap(
    RuntimeContext next, {
    Duration drainTimeout = const Duration(seconds: 5),
  }) async {
    if (identical(_current, next)) return;
    final old = _current;
    _current = next; // synchronous publish — new ops see it immediately
    _generation++;
    _changes.add(
      StoragePlaneChange(
        oldContext: old,
        newContext: next,
        generation: _generation,
      ),
    );
    await retire?.call(old);
  }

  /// Test seam mirroring `AppPathsBootstrapper`-based installs: a native
  /// context rooted at [paths] over an injected [filesystem].
  @visibleForTesting
  factory HomeStorage.forTesting({
    required Filesystem filesystem,
    required AppPaths paths,
    String home = '/home/test',
    String cwd = '/home/test',
  }) {
    return HomeStorage(
      RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: filesystem,
        home: home,
        cwd: cwd,
        appDataRoot: paths.basePath,
        paths: paths,
      ),
    );
  }

}
