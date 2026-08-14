import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'html_preview_server.dart';

/// Host-side surface for one html preview. Implementations wrap the platform
/// webview engine (webview_flutter official API on all platforms; Linux/Windows
/// use webview_win_floating under the platform interface).
abstract interface class HtmlWebViewController {
  Widget buildWidget(BuildContext context);

  Future<void> loadRequest(Uri uri);

  Future<void> reload();

  Future<void> dispose();
}

/// Production controller backed by the official webview_flutter API.
class WebviewHtmlController implements HtmlWebViewController {
  WebviewHtmlController()
    : _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

  final WebViewController _controller;

  @override
  Widget buildWidget(BuildContext context) => WebViewWidget(controller: _controller);

  @override
  Future<void> loadRequest(Uri uri) => _controller.loadRequest(uri);

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> dispose() async {}
}

/// Binds one mounted html directory to a webview controller for the lifetime
/// of a preview tab.
class HtmlPreviewSession {
  HtmlPreviewSession({
    required this.htmlDirectory,
    required this.entryFileName,
    required this.server,
    required this.controllerFactory,
  });

  final String htmlDirectory;
  final String entryFileName;
  final HtmlPreviewServer server;
  final HtmlWebViewController Function(Uri initialUri) controllerFactory;

  HtmlPreviewMount? _mount;
  HtmlWebViewController? _controller;

  HtmlWebViewController? get controller => _controller;
  HtmlPreviewMount? get mount => _mount;

  Future<HtmlPreviewMount?> start() async {
    final mount = await server.mount(
      htmlDirectory: htmlDirectory,
      entryFileName: entryFileName,
    );
    if (mount == null) return null;
    _mount = mount;
    final controller = controllerFactory(mount.entryUri);
    _controller = controller;
    await controller.loadRequest(mount.entryUri);
    return mount;
  }

  Future<void> reload() async {
    await _controller?.reload();
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    final mount = _mount;
    _mount = null;
    if (mount != null) {
      await server.unmount(mount.mountId);
    }
  }
}
