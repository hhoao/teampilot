import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import 'runtime_context.dart';
import 'work_target_canonicalizer.dart';

/// Bridges the directory-picker UI to runtime-target resolution, so dialogs
/// don't have to wire up the context registry / target catalog themselves.
///
/// Constructed at bootstrap from `RuntimeContextRegistry.forTarget` and
/// `RuntimeTargetRegistry.listTargets`, then provided to the widget tree.
class WorkspaceDirectoryPicker {
  WorkspaceDirectoryPicker({
    required Future<RuntimeContext> Function(RuntimeTarget) resolveContext,
    required Future<List<RuntimeTarget>> Function() listTargets,
  }) : _resolveContext = resolveContext,
       _listTargets = listTargets;

  final Future<RuntimeContext> Function(RuntimeTarget) _resolveContext;
  final Future<List<RuntimeTarget>> Function() _listTargets;

  /// Whether [targetId] resolves to an SSH (remote) machine — the only kind
  /// that needs the SFTP remote browser instead of the native picker.
  bool isRemote(String targetId) =>
      runtimeKindOfId(targetId) == RuntimeKind.ssh;

  /// The target matching [id] from the live catalog. An id the catalog does not
  /// know keeps its own kind instead of collapsing to local: the catalog lists
  /// workspace (B) hosts only, while an SSH home is bound in the device-local
  /// (A) catalog — mapping that id to local would make the remote browser list
  /// the device disk.
  Future<RuntimeTarget> targetById(String id) async {
    final trimmed = id.trim();
    final targets = await _listTargets();
    for (final t in targets) {
      if (t.id == trimmed) return t;
    }
    if (trimmed.isEmpty || trimmed == RuntimeTarget.localId) {
      return RuntimeTarget.local();
    }
    return WorkTargetCanonicalizer.fromId(trimmed).copyWith(label: trimmed);
  }

  /// The runtime context for [targetId] (triggers a real SSH connect for ssh
  /// targets — acceptable when the user explicitly opens a remote browser).
  ///
  /// An ssh target must resolve to a remote backend; a native result means the
  /// profile was missing from every catalog, and browsing it would list the
  /// device-local disk.
  Future<RuntimeContext> contextFor(String targetId) async {
    final ctx = await _resolveContext(await targetById(targetId));
    if (isRemote(targetId) && !ctx.fs.isRemote) {
      throw WorkspaceDirectoryPickerException(
        'Target "$targetId" resolved to a non-remote filesystem',
      );
    }
    return ctx;
  }

  /// The filesystem for [targetId].
  Future<Filesystem> filesystemFor(String targetId) async =>
      (await contextFor(targetId)).fs;
}

/// Raised when a target cannot provide the filesystem its kind promises.
class WorkspaceDirectoryPickerException implements Exception {
  const WorkspaceDirectoryPickerException(this.message);

  final String message;

  @override
  String toString() => 'WorkspaceDirectoryPickerException: $message';
}
