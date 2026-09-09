import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'app_paths.dart';
import 'home_storage.dart';
import 'runtime_context.dart';

export 'app_paths.dart';

/// Global business storage facade for the **control plane**: forwards to the
/// bound home [RuntimeContext]. Bind once at bootstrap via [bindHome]
/// (`RuntimeContextRegistry` pushes its `home()` here). Work-plane consumers
/// resolve their own context via the registry instead of this facade.
class AppStorage {
  AppStorage._();

  // ---- temporary migration shim — deleted in sub-task 6-C ----
  // When a HomeStorage is bound (bootstrap does so right after bindHome), it
  // is the source of truth: every getter forwards to its *current* context so
  // home swaps published via HomeStorage.swap propagate to unmigrated
  // consumers automatically. The legacy `_legacyHome` field only serves paths
  // that bind a context directly (tests via installForTesting).
  static HomeStorage? _homeStorage;
  static RuntimeContext? _legacyHome;

  /// Bind the home context (control plane). Synchronous so test setup stays
  /// non-async; the registry calls this after ensureHome/rebindHome.
  static void bindHome(RuntimeContext home) => _legacyHome = home;

  /// Bind the versioned home facade; thereafter this global forwards to it.
  static void bindHomeStorage(HomeStorage storage) => _homeStorage = storage;

  static void unbindHome() => _legacyHome = null;

  static RuntimeContext? get _bound => _homeStorage?.context ?? _legacyHome;

  static bool get isInstalled => _bound != null;

  static RuntimeContext get context =>
      _bound ??
      (throw StateError(
        'AppStorage home not bound; call AppStorage.bindHome() at bootstrap.',
      ));

  /// Shim-era tolerant fallback for consumers constructed without an injected
  /// [HomeStorage] (pre-6-C tests): the bound home facade when one exists,
  /// otherwise a native default context over [LocalFilesystem] — the same
  /// tolerance the legacy `fs` getter had when nothing was bound. Deleted in
  /// 6-C together with the rest of this shim.
  static HomeStorage get tolerantHome {
    final facade = _homeStorage;
    if (facade != null) return facade;
    final legacy = _legacyHome;
    if (legacy != null) return HomeStorage(legacy);
    return _unboundNativeHome;
  }

  /// The [tolerantHome] context used when nothing is bound at all. Roots point
  /// at a system-temp directory so a stray unbound write stays out of the real
  /// home; pre-6-C only `fs` was reachable unbound (everything else threw), so
  /// the path values only matter to code that would previously have failed.
  static final HomeStorage _unboundNativeHome = HomeStorage(
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: LocalFilesystem(),
      home: unboundNativeRoot,
      cwd: unboundNativeRoot,
      appDataRoot: unboundNativeRoot,
      paths: AppPaths(unboundNativeRoot),
    ),
  );

  /// System-temp root for the unbound native default (also used by
  /// [HomeStorage.nativeDefault]).
  static final String unboundNativeRoot = () {
    final root = p.join(Directory.systemTemp.path, 'teampilot-unbound-home');
    try {
      Directory(root).createSync(recursive: true);
    } on Object {
      // Read-only temp / sandboxed host: the path still works for joins.
    }
    return root;
  }();

  static Filesystem get fs => _bound?.filesystem ?? LocalFilesystem();

  static AppPaths get paths => context.paths;

  static String get home => context.home;

  /// Default workspace for new workspaces and CLI sessions (native: app Documents).
  static String get cwd => context.cwd;

  static String get appDataRoot => context.appDataRoot;

  static bool get usesPosixPaths => context.usesPosixPaths;

  /// Test seam: bind a native home context rooted at [paths] (replaces the old
  /// the removed global storage singleton install).
  @visibleForTesting
  static void installForTesting({
    required Filesystem filesystem,
    required AppPaths paths,
    String home = '/home/test',
    String cwd = '/home/test',
  }) {
    _homeStorage = null; // test install wins over any bound facade
    bindHome(
      RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: filesystem,
        home: home,
        cwd: cwd,
        appDataRoot: paths.basePath,
        paths: paths,
      ),
    );
    AppPathsBootstrapper.syncPaths(paths);
  }

  @visibleForTesting
  static void resetForTesting() {
    _homeStorage = null;
    unbindHome();
  }
}
