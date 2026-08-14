import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late InMemoryFilesystem fs;
  late HtmlPreviewServer server;

  setUp(() async {
    fs = InMemoryFilesystem();
    await fs.ensureDir('/repo');
    await fs.writeString('/repo/index.html', '<h1>Hello</h1>');
    await fs.writeString('/repo/style.css', 'body { color: red; }');
    await fs.writeString('/repo/sub/app.js', 'console.log(1);');
    await fs.writeString('/repo/secret.key', 'do-not-serve');
    server = HtmlPreviewServer(fs: fs);
  });

  tearDown(() async {
    await server.dispose();
  });

  Future<(int, String)> getBody(HttpClient client, Uri uri) async {
    final req = await client.getUrl(uri);
    final res = await req.close();
    return (res.statusCode, await res.transform(utf8.decoder).join());
  }

  test('mount serves entry file with html mime', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    expect(mount, isNotNull);
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri);
      final response = await res.close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(await response.transform(utf8.decoder).join(), '<h1>Hello</h1>');
    } finally {
      client.close();
    }
  });

  test('serves relative subresources', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final css = await client.getUrl(mount!.entryUri.resolve('style.css'));
      final cssRes = await css.close();
      expect(cssRes.statusCode, 200);
      expect(await cssRes.transform(utf8.decoder).join(), 'body { color: red; }');

      final js = await client.getUrl(mount.entryUri.resolve('sub/app.js'));
      final jsRes = await js.close();
      expect(jsRes.statusCode, 200);
    } finally {
      client.close();
    }
  });

  test('rejects path traversal outside mount root', () async {
    await fs.writeString('/secret.txt', 'top secret');
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final base = mount!.entryUri;
      for (final attempt in [
        base.resolve('../secret.txt'),
        base.resolve('../../etc/passwd'),
        Uri.parse(base.toString().replaceFirst('index.html', '%2e%2e/secret.txt')),
      ]) {
        final (status, _) = await getBody(client, attempt);
        expect(status, 404, reason: 'must reject $attempt');
      }
    } finally {
      client.close();
    }
  });

  test('rejects unknown extensions (deny by default)', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri.resolve('secret.key'));
      final response = await res.close();
      expect(response.statusCode, 404);
    } finally {
      client.close();
    }
  });

  test('missing file is 404', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri.resolve('nope.html'));
      final response = await res.close();
      expect(response.statusCode, 404);
    } finally {
      client.close();
    }
  });

  test('mount dedupes same directory and refcounts', () async {
    final a = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final b = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    expect(a!.mountId, b!.mountId);
    await server.unmount(a.mountId);
    expect(server.isServing(a.mountId), isTrue);
    await server.unmount(a.mountId);
    expect(server.isServing(a.mountId), isFalse);
  });

  test('unmounted mount 404s', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final ok = await client.getUrl(mount!.entryUri);
      expect((await ok.close()).statusCode, 200);
      await server.unmount(mount.mountId);
      final gone = await client.getUrl(mount.entryUri);
      expect((await gone.close()).statusCode, 404);
    } finally {
      client.close();
    }
  });

  test('reads through injected filesystem (ssh-equivalent)', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    await fs.writeString('/repo/index.html', 'updated');
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri);
      final response = await res.close();
      expect(await response.transform(utf8.decoder).join(), 'updated');
    } finally {
      client.close();
    }
  });
}
