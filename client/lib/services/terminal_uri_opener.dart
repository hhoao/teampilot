import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Opens terminal hyperlinks like gnome-terminal ([gtk_show_uri] semantics).
abstract final class TerminalUriOpener {
  static Future<bool> open(String raw) async {
    final uriString = fixup(raw);
    if (uriString == null) return false;

    final uri = Uri.tryParse(uriString);
    if (uri == null) return false;

    if (uri.scheme == 'file') {
      return _openFile(uri);
    }

    if (uri.scheme == 'mailto') {
      if (!await canLaunchUrl(uri)) return false;
      return launchUrl(uri);
    }

    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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

  static Future<bool> _openFile(Uri uri) async {
    final path = uri.toFilePath(windows: Platform.isWindows);
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

    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
