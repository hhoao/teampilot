import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] in the system default application.
///
/// On Linux this uses the XDG Desktop Portal OpenURI (via gdbus) instead of
/// url_launcher's gtk_show_uri_on_window: the portal is handled by the
/// desktop shell, which activates the target application's window — so the
/// browser actually jumps to the foreground instead of opening in the
/// background. Falls back to url_launcher when the portal is unavailable.
Future<void> openExternalUri(Uri uri) async {
  if (!kIsWeb && Platform.isLinux) {
    if (await _openViaPortal(uri)) return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // launchUrl can throw when no handler is installed; swallow so the
    // fire-and-forget call sites never surface unhandled async errors.
  }
}

Future<bool> _openViaPortal(Uri uri) async {
  try {
    final result = await Process.run('gdbus', [
      'call',
      '--session',
      '--dest',
      'org.freedesktop.portal.Desktop',
      '--object-path',
      '/org/freedesktop/portal/desktop',
      '--method',
      'org.freedesktop.portal.OpenURI.OpenURI',
      '', // parent window: none
      uri.toString(),
      '{}', // options
    ]);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}
