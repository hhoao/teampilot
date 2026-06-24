import '../io/filesystem.dart';
import '../storage/runtime_layout.dart';
import 'materialization_manifest.dart';

/// Materializes a member's runtime *ancestry* onto a remote work machine so the
/// existing inheritance (symlink `agents`, plugins, …) closes **within that
/// machine's root** (P3c §3.3). The local app is the only process that can reach
/// both filesystems: it reads home fs and writes the work machine fs.
///
/// 1. Copy home `cli-defaults/{tool}` + the workspace's config tree to the work
///    machine `<machineRoot>` at the same root-relative paths (content-hash skip
///    via [MaterializationManifest] — unchanged subtrees aren't re-copied).
/// 2. Run the existing `RuntimeLayout` inheritance with the **work** fs + root,
///    so `_ensureInheritedChild` links source/target both under `<machineRoot>`.
///
/// fs/runner injected → unit-testable with two [Filesystem]s (no real SFTP).
class WorkMachineMaterializer {
  WorkMachineMaterializer({
    required this.homeFs,
    required this.homeRoot,
    required this.workFs,
    required this.machineRoot,
    required this.manifest,
  })  : _homeLayout = RuntimeLayout(teampilotRoot: homeRoot, fs: homeFs),
        _workLayout = RuntimeLayout(teampilotRoot: machineRoot, fs: workFs);

  final Filesystem homeFs;
  final String homeRoot;
  final Filesystem workFs;
  final String machineRoot;
  final MaterializationManifest manifest;

  final RuntimeLayout _homeLayout;
  final RuntimeLayout _workLayout;

  /// Materializes ancestry for [tools] + [workspaceId], then closes the
  /// workspace→app inheritance in-root. Session→workspace closure is launch-time
  /// ([ensureSessionInheritance]).
  Future<void> reconcile({
    required Set<String> tools,
    required String workspaceId,
  }) async {
    final hashes = await manifest.load();
    for (final tool in tools) {
      await _copySubtree(
        homeFs.pathContext
            .relative(_homeLayout.appToolRoot(tool), from: homeRoot),
        hashes,
      );
      await _copySubtree(
        homeFs.pathContext.relative(
          _homeLayout.workspaceConfigToolDir(workspaceId, tool),
          from: homeRoot,
        ),
        hashes,
      );
    }
    await manifest.save(hashes);

    for (final tool in tools) {
      await _workLayout.ensureWorkspaceConfigInheritsApp(workspaceId, tool);
    }
  }

  /// Launch-time: close the session-runtime → workspace inheritance for a member
  /// on the work machine (symlinks resolve in-root).
  Future<void> ensureSessionInheritance({
    required String workspaceId,
    required String sessionId,
    required String tool,
    String? memberId,
  }) =>
      _workLayout.ensureSessionRuntimeInheritsWorkspace(
        workspaceId,
        sessionId,
        tool,
        memberId: memberId,
      );

  /// Copies every file under home `<homeRoot>/<relDir>` to the work machine
  /// `<machineRoot>/<relDir>`, skipping files whose content hash matches the
  /// manifest. [hashes] is updated in place (caller persists).
  Future<void> _copySubtree(String relDir, Map<String, String> hashes) async {
    final homeDir = homeFs.pathContext.join(homeRoot, relDir);
    if (!(await homeFs.stat(homeDir)).exists) return;
    final entries = await homeFs.listDirRecursive(homeDir);
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final homePath = homeFs.pathContext.join(homeDir, entry.name);
      final bytes = await homeFs.readBytes(homePath);
      if (bytes == null) continue;
      final key = homeFs.pathContext.relative(homePath, from: homeRoot);
      final hash = manifest.hashOf(bytes);
      if (hashes[key] == hash) continue; // unchanged → skip re-copy
      final workPath = workFs.pathContext.join(machineRoot, key);
      await workFs.writeBytes(workPath, bytes);
      hashes[key] = hash;
    }
  }
}
