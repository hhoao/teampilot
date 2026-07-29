import 'dart:io';

import 'package:path/path.dart' as p;

import '../inline_token/inline_token_palette.dart';
import '../../utils/workspace/workspace_path_utils.dart';

class ComposeAtFileRef {
  const ComposeAtFileRef({
    required this.absolutePath,
    required this.displayName,
  });

  final String absolutePath;
  final String displayName;
}

bool _isWindowsStylePath(String path) =>
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path.trim());

String _pathKey(String path) {
  if (Platform.isWindows || _isWindowsStylePath(path)) {
    return path.toLowerCase();
  }
  return path;
}

bool _isAbsoluteRefBody(String body) =>
    body.startsWith('/') || _isWindowsStylePath(body);

String resolveComposeAtFileAbsolutePath(
  String refBody, {
  required String workspaceRoot,
}) {
  final body = refBody.trim();
  if (body.isEmpty) return '';
  if (_isAbsoluteRefBody(body)) {
    return normalizeWorkspacePath(body.replaceAll(r'\', '/'));
  }
  final root = normalizeWorkspacePath(workspaceRoot);
  if (root.isEmpty) return normalizeWorkspacePath(body.replaceAll(r'\', '/'));
  final joined = p.Context(style: p.Style.posix).join(
    root.replaceAll(r'\', '/'),
    body.replaceAll(r'\', '/'),
  );
  return normalizeWorkspacePath(joined);
}

List<ComposeAtFileRef> parseComposeAtFileRefs(
  String text, {
  required String workspaceRoot,
}) {
  final seen = <String>{};
  final out = <ComposeAtFileRef>[];
  for (final match in defaultInlineTokenPattern.allMatches(text)) {
    final token = match.group(0)!;
    if (!token.startsWith('@')) continue;
    final body = token.substring(1);
    if (body.isEmpty) continue;
    final absolute = resolveComposeAtFileAbsolutePath(
      body,
      workspaceRoot: workspaceRoot,
    );
    if (absolute.isEmpty) continue;
    final key = _pathKey(absolute);
    if (!seen.add(key)) continue;
    out.add(
      ComposeAtFileRef(
        absolutePath: absolute,
        displayName: p.basename(absolute),
      ),
    );
  }
  return out;
}
