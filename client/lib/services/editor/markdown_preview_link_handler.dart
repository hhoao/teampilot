import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../services/editor/file_editor_theme.dart';
import '../workbench/workbench_editor_opener.dart';

/// Resolves markdown preview link taps for the IDE preview surface.
Future<void> handleMarkdownPreviewLink({
  required String? href,
  required String markdownFilePath,
  required String workspaceId,
  required List<String> workspaceRoots,
  required WorkbenchEditorOpener opener,
}) async {
  final raw = href?.trim() ?? '';
  if (raw.isEmpty) return;

  final uri = Uri.tryParse(raw);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }

  // file:// or absolute / relative path — open in editor when under workspace.
  String candidate;
  if (uri != null && uri.scheme == 'file') {
    candidate = uri.toFilePath();
  } else if (p.isAbsolute(raw)) {
    candidate = raw;
  } else {
    candidate = p.normalize(p.join(p.dirname(markdownFilePath), raw));
  }

  if (!isEditorOpenableFilePath(candidate)) return;
  final ctx = p.Context();
  final normalized = ctx.normalize(candidate);
  final underWorkspace = workspaceRoots.any((root) {
    if (root.isEmpty) return false;
    final nRoot = ctx.normalize(root);
    return normalized == nRoot || ctx.isWithin(nRoot, normalized);
  });
  if (!underWorkspace) return;
  await opener.openFile(workspaceId, normalized, preview: true);
}
