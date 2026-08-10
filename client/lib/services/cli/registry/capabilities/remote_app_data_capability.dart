import '../../../io/filesystem.dart';
import '../cli_capability.dart';

/// Whether this CLI needs shared plugin deps seeded on the remote home
/// before provider reconciliation.
abstract interface class RemoteAppDataCapability implements CliCapability {
  bool get needsSharedPluginDepsBeforeReconcile;

  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  });
}
