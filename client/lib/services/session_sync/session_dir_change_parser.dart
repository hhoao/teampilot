import 'package:path/path.dart' as p;

/// Workspace ids whose `sessions` directory changed.
///
/// The desktop authority watches the shared home's workspace root. A mobile
/// client writes a session over SFTP, which surfaces as a structural change on
/// `<workspaceRoot>/workspaces/<id>/sessions`, or on a child session directory.
/// Only paths under a `sessions` directory are returned; manifest/workbench
/// churn is ignored.
Set<String> workspaceIdsFromSessionChangeDirs(
  Iterable<String> changedDirs, {
  required String workspaceRoot,
  required p.Context pathContext,
}) {
  final marker =
      '${pathContext.join(workspaceRoot, 'workspaces')}'
      '${pathContext.separator}';
  final ids = <String>{};
  for (final dir in changedDirs) {
    if (!dir.startsWith(marker)) continue;
    final rest = dir.substring(marker.length);
    final parts = pathContext.split(rest);
    if (parts.length < 2 || parts[1] != 'sessions') continue;
    final id = parts[0].trim();
    if (id.isNotEmpty) ids.add(id);
  }
  return ids;
}
