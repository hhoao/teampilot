import 'path_projection.dart';

/// What to do with a path dragged across a machine boundary (e.g. a local file
/// dropped onto an SSH terminal). Pluggable so the future "upload then paste the
/// remote path" behavior is a new implementation, not an edit to drop targets.
abstract interface class CrossNamespaceStrategy {
  /// Resolve [path] (already known to be cross-namespace) into terminal-ready
  /// text, or `null` if it cannot be delivered. Implementations that transfer
  /// files do so here and return the projected remote path.
  Future<String?> resolve(CrossNamespacePath path);
}

/// Default: refuse cross-namespace drops. The path is not delivered; the caller
/// reports the rejection to the user. Keeps v1 free of file-transfer machinery
/// while leaving an `UploadAndProjectStrategy` slot for later.
class RejectCrossNamespaceStrategy implements CrossNamespaceStrategy {
  const RejectCrossNamespaceStrategy();

  @override
  Future<String?> resolve(CrossNamespacePath path) async => null;
}
