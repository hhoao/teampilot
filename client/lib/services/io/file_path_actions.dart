import 'dart:io' show Platform, Process;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../storage/runtime_context.dart';
import 'runtime_folder_opener.dart';
import 'system_folder_opener.dart';
import 'system_terminal_opener.dart';

typedef ClipboardWriter = Future<void> Function(String text);

typedef ExternalFileOpener = void Function(String filePath);

/// Resolves the longest workspace folder that contains [absolutePath].
String? resolveContainingWorkspaceRoot(
  String absolutePath,
  Iterable<String> folderPaths, {
  p.Context? pathContext,
}) {
  final ctx = pathContext ?? p.context;
  final normalized = ctx.normalize(absolutePath);
  String? best;
  var bestLen = -1;
  for (final raw in folderPaths) {
    final root = ctx.normalize(raw);
    final prefix = root.endsWith(ctx.separator) ? root : '$root${ctx.separator}';
    if (normalized == root || normalized.startsWith(prefix)) {
      if (root.length > bestLen) {
        best = root;
        bestLen = root.length;
      }
    }
  }
  return best;
}

/// Returns a path relative to [workspaceRoot], or null when not relativizable.
String? tryRelativeWorkspacePath({
  required String absolutePath,
  required String? workspaceRoot,
  p.Context? pathContext,
}) {
  if (workspaceRoot == null || workspaceRoot.isEmpty) return null;
  final ctx = pathContext ?? p.context;
  final root = ctx.normalize(workspaceRoot);
  final file = ctx.normalize(absolutePath);
  if (!ctx.isWithin(root, file) && file != root) return null;
  return ctx.relative(file, from: root);
}

/// Shared file-path clipboard and opener actions for file tree and tab menus.
abstract final class FilePathActions {
  FilePathActions._();

  static Future<void> copyAbsolutePath(
    String path, {
    ClipboardWriter? clipboardWriter,
  }) async {
    final writer =
        clipboardWriter ??
        (text) => Clipboard.setData(ClipboardData(text: text));
    await writer(path);
  }

  static Future<void> copyRelativePath({
    required String absolutePath,
    required String? workspaceRoot,
    p.Context? pathContext,
    ClipboardWriter? clipboardWriter,
  }) async {
    final relative = tryRelativeWorkspacePath(
      absolutePath: absolutePath,
      workspaceRoot: workspaceRoot,
      pathContext: pathContext,
    );
    if (relative == null) return;
    await copyAbsolutePath(relative, clipboardWriter: clipboardWriter);
  }

  static Future<void> revealInFileManager({
    required String targetPath,
    required bool isDirectory,
    required bool remoteFileManagerActions,
    RuntimeContext? workContext,
    SystemFolderOpener? systemFolderOpener,
    RuntimeFolderOpener? runtimeFolderOpener,
  }) async {
    final path = isDirectory
        ? targetPath
        : SystemFolderOpener.revealPathForFile(targetPath);
    if (remoteFileManagerActions) {
      await (runtimeFolderOpener ?? RuntimeFolderOpener()).reveal(
        path: path,
        workContext: workContext,
      );
      return;
    }
    await (systemFolderOpener ?? SystemFolderOpener()).reveal(path);
  }

  static Future<bool> openInTerminal({
    required String targetPath,
    required bool isDirectory,
    SystemTerminalOpener? terminalOpener,
  }) async {
    final dir = isDirectory
        ? targetPath
        : SystemFolderOpener.revealPathForFile(targetPath);
    return (terminalOpener ?? SystemTerminalOpener()).openAt(dir);
  }

  static void openWithSystemApp(
    String filePath, {
    ExternalFileOpener? opener,
    bool? isLinux,
    bool? isMacOS,
    bool? isWindows,
  }) {
    if (opener != null) {
      opener(filePath);
      return;
    }
    try {
      final linux = isLinux ?? Platform.isLinux;
      final macOS = isMacOS ?? Platform.isMacOS;
      final windows = isWindows ?? Platform.isWindows;
      if (linux) {
        Process.run('xdg-open', [filePath]);
      } else if (macOS) {
        Process.run('open', [filePath]);
      } else if (windows) {
        Process.run('start', [filePath], runInShell: true);
      }
    } catch (_) {}
  }
}
