import 'dart:async';
import 'dart:io';

import '../io/filesystem.dart';

/// One mounted html directory on a shared [HtmlPreviewServer].
class HtmlPreviewMount {
  const HtmlPreviewMount({required this.mountId, required this.entryUri});

  final String mountId;
  final Uri entryUri;
}

class _Mount {
  _Mount({
    required this.mountId,
    required this.fs,
    required this.htmlDirectory,
    required this.entryFileName,
  });

  final String mountId;
  final Filesystem fs;
  final String htmlDirectory;
  final String entryFileName;
  int refs = 1;
}

/// Local HTTP proxy that serves files from a mounted directory through a
/// [Filesystem] abstraction (native / WSL / SFTP), so the embedded webview can
/// render html from any storage backend.
///
/// One instance binds one loopback port shared by all its mounts. Callers
/// typically create one instance per preview pane with the current
/// [AppStorage.fs]; mounts are deduped and reference-counted inside one
/// instance.
class HtmlPreviewServer {
  HtmlPreviewServer({required Filesystem fs}) : _fs = fs;

  final Filesystem _fs;
  HttpServer? _server;
  final Map<String, _Mount> _mounts = {};
  int _nextId = 0;

  int? get port => _server?.port;

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    _server = server;
    return server;
  }

  Future<HtmlPreviewMount?> mount({
    required String htmlDirectory,
    required String entryFileName,
  }) async {
    // Dedupe identical mounts (same fs identity + directory + entry).
    for (final m in _mounts.values) {
      if (identical(m.fs, _fs) &&
          m.htmlDirectory == htmlDirectory &&
          m.entryFileName == entryFileName) {
        m.refs++;
        return HtmlPreviewMount(
          mountId: m.mountId,
          entryUri: Uri.parse(
            'http://127.0.0.1:${(await _ensureServer()).port}/m/${m.mountId}/$entryFileName',
          ),
        );
      }
    }
    final server = await _ensureServer();
    final mountId = 'h${_nextId++}';
    final mount = _Mount(
      mountId: mountId,
      fs: _fs,
      htmlDirectory: htmlDirectory,
      entryFileName: entryFileName,
    );
    _mounts[mountId] = mount;
    return HtmlPreviewMount(
      mountId: mountId,
      entryUri: Uri.parse(
        'http://127.0.0.1:${server.port}/m/$mountId/$entryFileName',
      ),
    );
  }

  bool isServing(String mountId) => _mounts.containsKey(mountId);

  Future<void> unmount(String mountId) async {
    final mount = _mounts[mountId];
    if (mount == null) return;
    mount.refs--;
    if (mount.refs > 0) return;
    _mounts.remove(mountId);
  }

  Future<void> dispose() async {
    _mounts.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }
      final path = req.uri.pathSegments;
      if (path.length < 3 || path[0] != 'm') {
        await _notFound(req);
        return;
      }
      final mountId = path[1];
      final mount = _mounts[mountId];
      if (mount == null) {
        await _notFound(req);
        return;
      }
      final relative = path.sublist(2).join('/');
      final ctx = mount.fs.pathContext;
      final root = ctx.normalize(mount.htmlDirectory);
      final candidate = ctx.normalize(ctx.join(root, relative));
      if (!ctx.isWithin(root, candidate)) {
        await _notFound(req);
        return;
      }
      final stat = await mount.fs.stat(candidate);
      if (!stat.isFile) {
        await _notFound(req);
        return;
      }
      final mime = _mimeFor(candidate);
      if (mime == null) {
        await _notFound(req);
        return;
      }
      final bytes = await mount.fs.readBytes(candidate);
      if (bytes == null) {
        await _notFound(req);
        return;
      }
      final res = req.response;
      res.statusCode = HttpStatus.ok;
      res.headers.contentType = ContentType.parse(mime);
      res.headers.set('Cache-Control', 'no-cache');
      if (req.method == 'HEAD') {
        res.contentLength = bytes.length;
        await res.close();
        return;
      }
      res.add(bytes);
      await res.close();
    } on Object {
      try {
        await _notFound(req);
      } on Object {
        // Client gone; nothing to do.
      }
    }
  }

  Future<void> _notFound(HttpRequest req) async {
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  static const _mimeByExtension = <String, String>{
    'html': 'text/html; charset=utf-8',
    'htm': 'text/html; charset=utf-8',
    'css': 'text/css',
    'js': 'text/javascript',
    'mjs': 'text/javascript',
    'json': 'application/json',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'txt': 'text/plain; charset=utf-8',
    'pdf': 'application/pdf',
  };

  static String? _mimeFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    return _mimeByExtension[path.substring(dot + 1).toLowerCase()];
  }
}
