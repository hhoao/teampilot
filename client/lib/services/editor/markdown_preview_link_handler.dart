import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../services/editor/file_editor_theme.dart';
import '../storage/app_storage.dart';
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

  // file:// is always a host-local path. Relative / absolute workspace paths
  // may be POSIX (SSH, WSL, in-memory tests) even when the host is Windows —
  // match [AppPaths.pathContextForDataRoot] so joins keep `/` separators.
  final String candidate;
  final p.Context ctx;
  if (uri != null && uri.scheme == 'file') {
    candidate = uri.toFilePath();
    ctx = p.context;
  } else {
    ctx = AppPaths.pathContextForDataRoot(markdownFilePath);
    if (ctx.isAbsolute(raw)) {
      candidate = raw;
    } else {
      candidate = ctx.normalize(ctx.join(ctx.dirname(markdownFilePath), raw));
    }
  }

  if (!isEditorOpenableFilePath(candidate)) return;
  final normalized = ctx.normalize(candidate);
  final underWorkspace = workspaceRoots.any((root) {
    if (root.isEmpty) return false;
    final rootCtx = AppPaths.pathContextForDataRoot(root);
    final nRoot = rootCtx.normalize(root);
    return normalized == nRoot || rootCtx.isWithin(nRoot, normalized);
  });
  if (!underWorkspace) return;
  await opener.openFile(workspaceId, normalized, preview: true);
}

/// Resolves markdown preview images: http(s) URLs or workspace-relative files.
ImageProvider? resolveMarkdownPreviewImage({
  required String src,
  required String markdownFilePath,
  required List<String> workspaceRoots,
}) {
  final raw = src.trim();
  if (raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return NetworkImage(uri.toString());
  }

  final p.Context ctx;
  final String candidate;
  if (uri != null && uri.scheme == 'file') {
    candidate = uri.toFilePath();
    ctx = p.context;
  } else {
    ctx = AppPaths.pathContextForDataRoot(markdownFilePath);
    if (ctx.isAbsolute(raw)) {
      candidate = raw;
    } else {
      candidate = ctx.normalize(ctx.join(ctx.dirname(markdownFilePath), raw));
    }
  }

  if (!isImagePreviewPath(candidate)) return null;
  final normalized = ctx.normalize(candidate);
  final underWorkspace = workspaceRoots.any((root) {
    if (root.isEmpty) return false;
    final rootCtx = AppPaths.pathContextForDataRoot(root);
    final nRoot = rootCtx.normalize(root);
    return normalized == nRoot || rootCtx.isWithin(nRoot, normalized);
  });
  if (!underWorkspace) return null;

  final file = File(candidate);
  if (!file.existsSync()) return null;
  return FileImage(file);
}
