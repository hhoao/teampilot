import '../../../utils/workspace_path_utils.dart';
import '../../io/filesystem.dart';
import 'cursor_workspace_trust.dart';

/// Writes Cursor CLI `.workspace-trusted` markers under `$HOME/.cursor/projects/`.
///
/// Used for personal / native team launches (real [homeRoot]) and mixed mode
/// (isolated fake [homeRoot]). Path variants follow [workspaceMetadataKeys] so
/// Windows / WSL slug lookups match `cursor-agent --workspace`.
final class CursorWorkspaceTrustProvisioner {
  CursorWorkspaceTrustProvisioner({required Filesystem fs}) : _fs = fs;

  final Filesystem _fs;

  /// Every workspace path string cursor-agent may resolve for a launch.
  static Set<String> workspacePathKeys({
    String? workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) {
    final keys = <String>{};
    void add(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return;
      keys.addAll(workspaceMetadataKeys(trimmed));
    }

    add(workingDirectory ?? '');
    for (final directory in additionalDirectories) {
      add(directory);
    }
    return keys;
  }

  Future<void> provisionLaunchWorkspaces({
    required String homeRoot,
    String? workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) => provision(
    homeRoot: homeRoot,
    workspacePaths: workspacePathKeys(
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
    ),
  );

  Future<void> provision({
    required String homeRoot,
    required Iterable<String> workspacePaths,
  }) async {
    final home = homeRoot.trim();
    if (home.isEmpty) return;

    for (final path in workspacePaths) {
      final normalized = path.trim();
      if (normalized.isEmpty) continue;

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(
        home,
        normalized,
        pathContext: _fs.pathContext,
      );
      await _fs.ensureDir(_fs.pathContext.dirname(trustPath));
      await _fs.atomicWrite(
        trustPath,
        CursorWorkspaceTrust.buildTrustMarkerJson(normalized),
      );
    }
  }
}
