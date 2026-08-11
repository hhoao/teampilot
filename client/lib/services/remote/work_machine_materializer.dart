import '../io/filesystem.dart';
import '../launch/launch_manifest_paths.dart';
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
  }) : _homeLayout = RuntimeLayout(teampilotRoot: homeRoot, fs: homeFs),
       _workLayout = RuntimeLayout(teampilotRoot: machineRoot, fs: workFs);

  /// Bounded concurrency for ancestry file copies (per-file SFTP round trips
  /// dominate first materialization; see [_copySubtree]).
  static const int copyWriteConcurrency = 8;

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
        homeFs.pathContext.relative(
          _homeLayout.appToolRoot(tool),
          from: homeRoot,
        ),
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
  }) => _workLayout.ensureSessionRuntimeInheritsWorkspace(
    workspaceId,
    sessionId,
    tool,
    memberId: memberId,
  );

  /// Copies every file under home `<homeRoot>/<relDir>` to the work machine
  /// `<machineRoot>/<relDir>`, skipping files whose content hash matches the
  /// manifest. [hashes] is updated in place (caller persists).
  ///
  /// Writes run through a worker pool bounded by [copyWriteConcurrency]: the
  /// first materialization ships a large tree (e.g. `cli-defaults/opencode`
  /// with npm `node_modules`) and each per-file SFTP write costs several
  /// network round trips, so serial writes dominate the launch time.
  Future<void> _copySubtree(String relDir, Map<String, String> hashes) async {
    final homeDir = homeFs.pathContext.join(homeRoot, relDir);
    if (!(await homeFs.stat(homeDir)).exists) return;
    final entries = await homeFs.listDirRecursive(homeDir);
    final files = [
      for (final entry in entries)
        if (!entry.isDirectory) entry.name,
    ];
    var next = 0;
    Future<void> copyNext() async {
      while (true) {
        final index = next++;
        if (index >= files.length) return;
        await _copyOne(files[index], homeDir, hashes);
      }
    }

    await Future.wait(
      [for (var i = 0; i < copyWriteConcurrency; i++) copyNext()],
      eagerError: true,
    );
  }

  Future<void> _copyOne(
    String name,
    String homeDir,
    Map<String, String> hashes,
  ) async {
    final homePath = homeFs.pathContext.join(homeDir, name);
    final bytes = await homeFs.readBytes(homePath);
    if (bytes == null) return;
    final homeKey = homeFs.pathContext.relative(homePath, from: homeRoot);
    final key = normalizeWorkPath(workFs, homeKey);
    final hash = manifest.hashOf(bytes);
    if (hashes[key] == hash) return; // unchanged → skip re-copy
    final workPath = workFs.pathContext.join(machineRoot, key);
    await workFs.writeBytes(workPath, bytes);
    hashes[key] = hash;
  }
}
