import '../io/filesystem.dart';

/// Centralized "make `target` point at `source`" strategy:
/// junction/symlink first (O(1)), copy as a fallback when the platform or
/// transport refuses symlinks (Windows without privilege, SFTP).
class LinkStrategy {
  const LinkStrategy(this._fs);

  final Filesystem _fs;

  /// Returns true if a symlink was created, false if it fell back to copy.
  Future<bool> link({
    required String source,
    required String target,
  }) async {
    final linked = await _fs.createSymlink(target: source, linkPath: target);
    if (linked) return true;
    await _fs.copyTree(source: source, destination: target);
    return false;
  }
}
