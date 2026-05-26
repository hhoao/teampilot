import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../editor/file_editor_theme.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Opens terminal hyperlinks like gnome-terminal ([gtk_show_uri] semantics).
abstract final class TerminalUriOpener {
  /// When set, existing local files are opened in the in-app editor before
  /// falling back to the OS handler.
  static Future<bool> open(
    String raw, {
    String? workingDirectory,
    Filesystem? fs,
    Future<void> Function(String absolutePath)? openInEditor,
  }) async {
    final uriString = fixup(raw);
    if (uriString == null) return false;

    final uri = Uri.tryParse(uriString);
    if (uri == null) return false;

    if (uri.scheme == 'file') {
      final path = resolveLocalFilePath(
        raw,
        workingDirectory: workingDirectory,
      );
      if (path != null &&
          openInEditor != null &&
          _shouldOpenInEditor(path)) {
        final filesystem = fs ?? AppStorage.fs;
        final stat = await filesystem.stat(path);
        if (stat.exists && stat.isFile) {
          await openInEditor(path);
          return true;
        }
      }
      return _openFilePath(
        path ?? uri.toFilePath(windows: Platform.isWindows),
      );
    }

    if (uri.scheme == 'mailto') {
      if (!await canLaunchUrl(uri)) return false;
      return launchUrl(uri);
    }

    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Resolves a terminal [file:] URI to an absolute path, using [workingDirectory]
  /// for relative targets when provided.
  static String? resolveLocalFilePath(
    String raw, {
    String? workingDirectory,
  }) {
    final uriString = fixup(raw);
    if (uriString == null) return null;

    final uri = Uri.tryParse(uriString);
    if (uri == null || uri.scheme != 'file') return null;

    var path = uri.toFilePath(windows: Platform.isWindows);
    if (path.isEmpty) return null;

    final wd = workingDirectory?.trim() ?? '';
    if (wd.isNotEmpty && _shouldJoinWithWorkingDirectory(uriString, path)) {
      final relative = path.replaceFirst(RegExp(r'^[\\/]+'), '');
      path = p.normalize(p.join(wd, relative));
    } else {
      path = p.normalize(path);
    }
    return path;
  }

  /// `file:/foo` yields `\foo` on Windows or `/foo` on POSIX — root-relative, not
  /// a full path; join with the session working directory when possible.
  static bool _shouldJoinWithWorkingDirectory(String uriString, String path) {
    if (path.isEmpty) return false;
    if (!p.isAbsolute(path)) return true;
    if (Platform.isWindows) {
      return !path.contains(':');
    }
    // POSIX: `file:/path` (two slashes) is cwd-relative; `file:///path` is absolute.
    final trimmed = uriString.trim();
    return trimmed.startsWith('file:/') && !trimmed.startsWith('file:///');
  }

  /// gnome-terminal [terminal_util_uri_fixup]: normalize file:// host, trim punctuation.
  static String? fixup(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    trimmed = trimmed.replaceAll(RegExp(r'[)\],.;:]+$'), '');

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    if (uri.scheme != 'file') return trimmed;

    final host = uri.host;
    if (host.isEmpty) return trimmed;

    final localHost = Platform.localHostname;
    if (host == 'localhost' ||
        host.toLowerCase() == localHost.toLowerCase()) {
      return uri.replace(host: '').toString();
    }

    // Remote file:// in SSH sessions — refuse like gnome-terminal.
    return null;
  }

  static bool _shouldOpenInEditor(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return !kEditorBinaryExtensions.contains(ext);
  }

  static Future<bool> _openFilePath(String path) async {
    if (path.isEmpty) return false;

    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [path], runInShell: true);
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [path], runInShell: true);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      final result = await Process.run(
        'cmd',
        ['/c', 'start', '', path],
        runInShell: true,
      );
      return result.exitCode == 0;
    }

    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
