import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../cubits/chat_cubit.dart';
import '../../services/editor/file_editor_theme.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../workbench/workbench_editor_opener.dart';
import '../workbench/workspace_href_handler.dart';
import '../workspace/workspace_tools_scope.dart';
import '../workspace/workspace_tools_scope_registry.dart';

/// Picks workspace roots for markdown preview link/image checks.
///
/// Prefer an inherited [WorkspaceToolsScope], then a registry peek (floating
/// panel is a Stack sibling of the workspace body), then folder paths.
List<String> coalesceMarkdownPreviewWorkspaceRoots({
  List<String>? scopeRoots,
  List<String>? registryRoots,
  List<String> folderPaths = const [],
}) {
  if (scopeRoots != null && scopeRoots.isNotEmpty) {
    return List<String>.unmodifiable(scopeRoots);
  }
  if (registryRoots != null && registryRoots.isNotEmpty) {
    return List<String>.unmodifiable(registryRoots);
  }
  return [
    for (final path in folderPaths)
      if (path.trim().isNotEmpty) path,
  ];
}

/// Resolves roots for IDE markdown preview from the nearest available source.
List<String> markdownPreviewWorkspaceRoots(
  BuildContext context, {
  required String workspaceId,
}) {
  final scope = WorkspaceToolsScope.maybeOf(context);
  final scopeRoots = _rootsFromScope(scope);

  final registry = _maybeRegistry(context);
  final peeked = registry?.peek(workspaceId);
  final registryRoots = peeked == null ? null : _rootsFromScope(peeked.state);

  final folderPaths =
      _maybeChat(context)?.state.workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull
          ?.folderPaths ??
      const <String>[];

  return coalesceMarkdownPreviewWorkspaceRoots(
    scopeRoots: scopeRoots,
    registryRoots: registryRoots,
    folderPaths: folderPaths,
  );
}

List<String> _rootsFromScope(WorkspaceToolsScopeState? scope) {
  if (scope == null) return const [];
  final seen = <String>{};
  final out = <String>[];
  void addAll(Iterable<String> paths) {
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      out.add(trimmed);
    }
  }

  addAll(scope.roots);
  for (final slice in scope.targetSlices) {
    addAll(slice.roots);
  }
  addAll(scope.effectiveFolders.map((f) => f.path));
  return out;
}

WorkspaceToolsScopeRegistry? _maybeRegistry(BuildContext context) {
  try {
    return context.read<WorkspaceToolsScopeRegistry>();
  } catch (_) {
    return null;
  }
}

ChatCubit? _maybeChat(BuildContext context) {
  try {
    return context.read<ChatCubit>();
  } catch (_) {
    return null;
  }
}

/// Resolves markdown preview link taps for the IDE preview surface.
Future<WorkspaceHrefOpenOutcome> handleMarkdownPreviewLink({
  required String? href,
  required String markdownFilePath,
  required String workspaceId,
  required List<String> workspaceRoots,
  required WorkbenchEditorOpener opener,
  required Filesystem fs,
  WorkspaceHrefHandler? handler,
}) {
  return (handler ?? WorkspaceHrefHandler(opener: opener)).open(
    href: href ?? '',
    workspaceId: workspaceId,
    workspaceRoots: workspaceRoots,
    searchBases: [
      AppPaths.pathContextForDataRoot(
        markdownFilePath,
      ).dirname(markdownFilePath),
    ],
    fs: fs,
  );
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
