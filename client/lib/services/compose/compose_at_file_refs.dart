import 'dart:io';

import 'package:path/path.dart' as p;

import '../inline_token/inline_token_palette.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
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
  required bool usesPosixPaths,
}) {
  final body = refBody.trim();
  if (body.isEmpty) return '';
  if (_isAbsoluteRefBody(body)) {
    return normalizeWorkspacePath(
      body.replaceAll(r'\', '/'),
      usesPosixPaths: usesPosixPaths,
    );
  }
  final root = normalizeWorkspacePath(
    workspaceRoot,
    usesPosixPaths: usesPosixPaths,
  );
  if (root.isEmpty) {
    return normalizeWorkspacePath(
      body.replaceAll(r'\', '/'),
      usesPosixPaths: usesPosixPaths,
    );
  }
  final joined = p.Context(style: p.Style.posix).join(
    root.replaceAll(r'\', '/'),
    body.replaceAll(r'\', '/'),
  );
  return normalizeWorkspacePath(joined, usesPosixPaths: usesPosixPaths);
}

List<ComposeAtFileRef> parseComposeAtFileRefs(
  String text, {
  required String workspaceRoot,
  required bool usesPosixPaths,
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
      usesPosixPaths: usesPosixPaths,
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

/// Filesystem for opening a compose `@` absolute path in the workbench.
///
/// Paste-imported images live under local `…/TeamPilot/Attachments` via
/// [LocalFilesystem]; other paths use [workspaceFilesystem] (the caller's
/// workspace backend filesystem, e.g. the home storage `fs`).
Filesystem filesystemForComposeAtFileOpen(
  String absolutePath, {
  required Filesystem workspaceFilesystem,
}) {
  final normalized = absolutePath.replaceAll(r'\', '/').toLowerCase();
  if (normalized.contains('/teampilot/attachments/')) {
    return LocalFilesystem();
  }
  return workspaceFilesystem;
}
