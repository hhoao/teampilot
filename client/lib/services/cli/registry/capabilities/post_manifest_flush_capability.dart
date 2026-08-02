import '../../../io/filesystem.dart';
import '../../../launch/work_plane_script_runner.dart';
import '../cli_capability.dart';

/// Context for CLI work after [LaunchManifest] has been flushed to the work
/// plane (local disk or SSH batch).
final class PostManifestFlushContext {
  const PostManifestFlushContext({
    required this.workFs,
    required this.workHome,
    required this.environment,
    this.remoteRunner,
    this.reportDetail,
  });

  /// Work-plane filesystem (local or SFTP).
  final Filesystem workFs;

  /// Real user home on the work plane (`RuntimeContext.home`).
  final String workHome;

  /// Staged launch environment (includes fake `HOME` when applicable).
  final Map<String, String> environment;

  /// Non-null on SSH/Termux work planes — prefer one remote script over SFTP.
  final WorkPlaneScriptRunner? remoteRunner;

  /// Optional progress detail for the provision UI (`cursor-home-passthrough`).
  final void Function(String detail)? reportDetail;
}

/// Optional per-CLI hook after session trees exist on the work plane.
///
/// CLIs without post-flush work simply omit this capability. Callers resolve
/// via [CliToolRegistry.capability] — never `if (cli == …)`.
abstract interface class PostManifestFlushCapability implements CliCapability {
  Future<void> afterManifestFlush(PostManifestFlushContext ctx);
}
