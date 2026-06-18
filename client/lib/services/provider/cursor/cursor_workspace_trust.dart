import 'dart:convert';

import 'package:path/path.dart' as p;

/// Cursor CLI workspace trust markers under `$HOME/.cursor/projects/`.
///
/// Matches cursor-agent `slugifyPath` + `Y(workspace)/.workspace-trusted`.
abstract final class CursorWorkspaceTrust {
  CursorWorkspaceTrust._();

  static const workspacesDirName = 'workspaces';
  static const trustFileName = '.workspace-trusted';
  static const trustMethod = 'teampilot-provisioned';

  /// Same rules as cursor-agent `slugifyPath` / `Pn`.
  static String slugifyWorkspacePath(String workspacePath) {
    final normalized = workspacePath.trim();
    if (normalized.isEmpty) return '';
    var slug = normalized.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');
    slug = slug.replaceAll(RegExp(r'-+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  static String workspaceDir(
    String homeRoot,
    String workspacePath, {
    p.Context? pathContext,
  }) {
    final ctx = pathContext ?? p.context;
    final slug = slugifyWorkspacePath(workspacePath);
    return ctx.join(homeRoot, '.cursor', workspacesDirName, slug);
  }

  static String trustMarkerPath(
    String homeRoot,
    String workspacePath, {
    p.Context? pathContext,
  }) =>
      (pathContext ?? p.context).join(
        workspaceDir(
          homeRoot,
          workspacePath,
          pathContext: pathContext,
        ),
        trustFileName,
      );

  static String buildTrustMarkerJson(String workspacePath) {
    return jsonEncode({
      'trustedAt': DateTime.now().toUtc().toIso8601String(),
      'workspacePath': workspacePath.trim(),
      'trustMethod': trustMethod,
    });
  }
}
