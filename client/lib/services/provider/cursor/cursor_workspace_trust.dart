import 'dart:convert';

import 'package:path/path.dart' as p;

/// Cursor CLI workspace trust markers under `$HOME/.cursor/projects/`.
///
/// Matches cursor-agent `slugifyPath` + `Y(workspace)/.workspace-trusted`.
abstract final class CursorWorkspaceTrust {
  CursorWorkspaceTrust._();

  static const projectsDirName = 'projects';
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

  static String projectDir(String homeRoot, String workspacePath) {
    final slug = slugifyWorkspacePath(workspacePath);
    return p.join(homeRoot, '.cursor', projectsDirName, slug);
  }

  static String trustMarkerPath(String homeRoot, String workspacePath) =>
      p.join(projectDir(homeRoot, workspacePath), trustFileName);

  static String buildTrustMarkerJson(String workspacePath) {
    return jsonEncode({
      'trustedAt': DateTime.now().toUtc().toIso8601String(),
      'workspacePath': p.normalize(workspacePath.trim()),
      'trustMethod': trustMethod,
    });
  }
}
