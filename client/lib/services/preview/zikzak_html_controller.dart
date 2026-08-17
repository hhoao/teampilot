import 'dart:async';

import 'package:flutter/material.dart';

import 'html_preview_session.dart';
import 'zikzak_webview_host.dart';

/// Linux preview controller backed by the shared [ZikzakWebViewHost].
///
/// The host owns the single zikzak webview (WebKitGTK cannot safely recreate
/// webviews inside one GTK process — the second recreate freezes the app),
/// so this controller only mirrors the host texture into the preview pane
/// and routes load/reload calls to it. Closing or switching the pane never
/// destroys the webview.
class ZikzakHtmlController implements HtmlWebViewController {
  ZikzakHtmlController({Uri? initialUri}) {
    final host = ZikzakWebViewHost.instance;
    if (host != null && initialUri != null) {
      unawaited(host.loadUrl(initialUri));
    }
  }

  @override
  Widget buildWidget(BuildContext context) {
    final host = ZikzakWebViewHost.instance;
    if (host == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int?>(
      valueListenable: host.textureIdNotifier,
      builder: (context, textureId, _) {
        if (textureId == null) {
          return const SizedBox.shrink();
        }
        return Texture(textureId: textureId);
      },
    );
  }

  @override
  Future<void> loadRequest(Uri uri) async {
    final host = ZikzakWebViewHost.instance;
    if (host == null) return;
    await host.loadUrl(uri);
  }

  @override
  Future<void> reload() async {
    final host = ZikzakWebViewHost.instance;
    if (host == null) return;
    await host.reload();
  }

  @override
  Future<void> dispose() async {
    // The host webview is app-lifetime and must survive pane teardown.
  }
}
