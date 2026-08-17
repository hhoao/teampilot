import 'html_preview_server.dart';

/// Binds one mounted html directory for the lifetime of a preview tab.
///
/// The preview itself is a standalone webview window (desktop_webview_window)
/// loaded from [HtmlPreviewServer]; the session only owns the server mount
/// lifecycle.
class HtmlPreviewSession {
  HtmlPreviewSession({
    required this.htmlDirectory,
    required this.entryFileName,
    required this.server,
  });

  final String htmlDirectory;
  final String entryFileName;
  final HtmlPreviewServer server;

  HtmlPreviewMount? _mount;

  HtmlPreviewMount? get mount => _mount;

  Future<HtmlPreviewMount?> start() async {
    final mount = await server.mount(
      htmlDirectory: htmlDirectory,
      entryFileName: entryFileName,
    );
    if (mount == null) return null;
    _mount = mount;
    return mount;
  }

  Future<void> dispose() async {
    final mount = _mount;
    _mount = null;
    if (mount != null) {
      await server.unmount(mount.mountId);
    }
  }
}
