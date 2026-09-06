import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../../cubits/chat_cubit.dart';
import '../../services/editor/file_editor_theme.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../workbench/workbench_editor_opener.dart';
import '../workbench/workspace_href_handler.dart';
import '../workspace/workspace_tools_scope.dart';
import '../workspace/workspace_tools_scope_registry.dart';
import '../../widgets/workbench/markdown_network_image.dart';

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

/// Resolves markdown preview images: workspace-relative raster files only.
///
/// http(s) sources (badges, remote screenshots — often SVG) and local SVGs are
/// handled by the widget layer, [buildMarkdownPreviewImage], because Flutter's
/// raster decoders reject SVG bytes; this provider hook returns null for them.
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
    return null;
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

/// Widget-level markdown preview image source. Owns every http(s) URL and
/// local `.svg` file:
///
/// - shields.io URLs are rewritten to PNG ([preferRasterBadgeUrl]) — their
///   SVG embeds logos as `<image href="data:image/svg+xml;base64,…">` (dropped
///   by flutter_svg) and uses `font-size="110"` / `110px` + `scale(.1)` text
///   that flutter_svg paints incorrectly.
/// - Other http(s) URLs go through [MarkdownNetworkImage] (SVG sniff +
///   normalize fallback, or raster).
/// - Workspace `.svg` files render through flutter_svg.
///
/// Returns null otherwise (raster workspace files fall back to
/// [resolveMarkdownPreviewImage]).
Widget? buildMarkdownPreviewImage({
  required String src,
  required String markdownFilePath,
  required List<String> workspaceRoots,
  bool inline = false,
  double? inlineHeight,
}) {
  final raw = src.trim();
  if (raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    final fetchUri = preferRasterBadgeUrl(uri);
    return _inlineSized(
      MarkdownNetworkImage(url: fetchUri.toString()),
      inline: inline,
      inlineHeight: inlineHeight,
    );
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

  if (!isSvgPreviewPath(candidate)) return null;
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
  return _inlineSized(
    SvgPicture.file(
      file,
      fit: BoxFit.scaleDown,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
    inline: inline,
    inlineHeight: inlineHeight,
  );
}

/// Prefer PNG for shields.io badge URLs.
///
/// shields.io SVG badges embed brand logos via nested `<image
/// href="data:image/svg+xml;base64,…">` (flutter_svg skips them) and encode
/// label text at `font-size="110"` / `110px` inside `scale(.1)` transforms
/// (flutter_svg paints that text unscaled). Their PNG endpoint bakes logos
/// and text correctly; GitHub Actions `badge.svg` and other hosts are left
/// unchanged.
Uri preferRasterBadgeUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host != 'img.shields.io' && host != 'shields.io') return uri;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return uri;
  final last = segments.last;
  final lower = last.toLowerCase();
  if (lower.endsWith('.png')) return uri;

  final rewritten = List<String>.from(segments);
  if (_hasShieldsImageExtension(lower)) {
    final dot = last.lastIndexOf('.');
    rewritten[rewritten.length - 1] = '${last.substring(0, dot)}.png';
  } else {
    // Badge labels often contain dots (`restcut.com`); those are not file
    // extensions — still append `.png`.
    rewritten[rewritten.length - 1] = '$last.png';
  }
  return uri.replace(pathSegments: rewritten);
}

bool _hasShieldsImageExtension(String lowerLastSegment) {
  return lowerLastSegment.endsWith('.svg') ||
      lowerLastSegment.endsWith('.gif') ||
      lowerLastSegment.endsWith('.jpg') ||
      lowerLastSegment.endsWith('.jpeg') ||
      lowerLastSegment.endsWith('.webp');
}

/// Inline images cap to the line box without upscaling — shields badges are
/// ~20px tall; forcing [SizedBox] height to a larger line box stretched (and
/// blurred) 1x rasters. Block images stay unconstrained.
Widget _inlineSized(
  Widget image, {
  required bool inline,
  double? inlineHeight,
}) {
  if (!inline || inlineHeight == null) return image;
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: inlineHeight),
    child: image,
  );
}

/// Whether [filePath] is an SVG image previewable by flutter_svg.
bool isSvgPreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && ext.startsWith('svg');
}
