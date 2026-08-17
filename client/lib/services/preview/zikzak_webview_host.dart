import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:zikzak_inappwebview/zikzak_inappwebview.dart';
import 'package:zikzak_inappwebview_linux/zikzak_inappwebview_linux.dart';

/// App-lifetime singleton that owns the single zikzak Linux webview.
///
/// WebKitGTK cannot safely tear down and recreate webviews inside one GTK
/// process (the second recreate freezes the app while the old WebProcess is
/// still exiting), so the preview pane never creates its own webview.
/// Instead this host is mounted once at the MaterialApp root (see
/// main.dart), creates the webview once, and every preview tab renders the
/// same texture via [textureIdNotifier] and navigates it with [loadUrl].
class ZikzakWebViewHost extends StatefulWidget {
  const ZikzakWebViewHost({super.key});

  static ZikzakWebViewHostState? instance;

  @override
  State<ZikzakWebViewHost> createState() => ZikzakWebViewHostState();
}

class ZikzakWebViewHostState extends State<ZikzakWebViewHost> {
  final ValueNotifier<int?> textureIdNotifier = ValueNotifier(null);

  InAppWebViewController? _controller;
  Uri? _pendingUri;

  @override
  void initState() {
    super.initState();
    ZikzakWebViewHost.instance = this;
  }

  @override
  void dispose() {
    if (ZikzakWebViewHost.instance == this) {
      ZikzakWebViewHost.instance = null;
    }
    textureIdNotifier.dispose();
    super.dispose();
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
    final platform = controller.platform;
    if (platform is LinuxInAppWebViewController) {
      textureIdNotifier.value = platform.textureId;
    }
    final uri = _pendingUri;
    if (uri != null) {
      _pendingUri = null;
      unawaited(
        controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(uri.toString())),
        ),
      );
    }
  }

  Future<void> loadUrl(Uri uri) async {
    final controller = _controller;
    if (controller == null) {
      _pendingUri = uri;
      return;
    }
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(uri.toString())),
    );
  }

  Future<void> reload() async {
    await _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    // Offstage but laid out at the offscreen render size: the native side
    // renders at the widget's allocation, so this must stay 1280x720 for a
    // usable texture even though nothing is visible here.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        offstage: true,
        child: SizedBox(
          width: 1280,
          height: 720,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('about:blank')),
            onWebViewCreated: _onWebViewCreated,
          ),
        ),
      ),
    );
  }
}
