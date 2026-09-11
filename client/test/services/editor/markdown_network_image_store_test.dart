import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/services/editor/markdown_network_image_store.dart';

final pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late Directory cacheDir;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('md-img-store');
    MarkdownNetworkImageStore.resetForTest();
  });

  tearDown(() {
    MarkdownNetworkImageStore.resetForTest();
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  test('concurrency gate never exceeds maxConcurrent in-flight fetches', () async {
    var inFlight = 0;
    var peak = 0;
    final store = MarkdownNetworkImageStore(
      cacheDir: cacheDir,
      maxConcurrent: 2,
      httpGet: (uri, {headers}) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        inFlight--;
        return http.Response.bytes(pngBytes, 200, headers: {
          'content-type': 'image/png',
          'etag': '"v1"',
        });
      },
    );

    final results = await Future.wait([
      for (var i = 0; i < 5; i++) store.load('https://example.com/b$i.png'),
    ]);
    expect(results.every((r) => r != null), isTrue);
    expect(peak, 2);
    expect(peak, lessThanOrEqualTo(2));
  });

  test('disk cache serves bytes without network on second store instance', () async {
    var fetches = 0;
    Future<http.Response?> get(Uri uri, {Map<String, String>? headers}) async {
      fetches++;
      return http.Response.bytes(pngBytes, 200, headers: {
        'content-type': 'image/png',
        'etag': '"abc"',
      });
    }

    final first = MarkdownNetworkImageStore(
      cacheDir: cacheDir,
      httpGet: get,
    );
    final a = await first.load('https://example.com/logo.png');
    expect(a, isNotNull);
    expect(fetches, 1);

    // New store, empty memory — must hit disk, not network.
    MarkdownNetworkImageStore.resetForTest();
    final second = MarkdownNetworkImageStore(
      cacheDir: cacheDir,
      httpGet: get,
    );
    final b = await second.load('https://example.com/logo.png');
    expect(b, isNotNull);
    expect(b!.bytes, pngBytes);
    expect(fetches, 1);
  });

  test('revalidate sends If-None-Match and keeps disk bytes on 304', () async {
    var fetches = 0;
    Map<String, String>? lastHeaders;
    Future<http.Response?> get(Uri uri, {Map<String, String>? headers}) async {
      fetches++;
      lastHeaders = headers;
      if (fetches == 1) {
        return http.Response.bytes(pngBytes, 200, headers: {
          'content-type': 'image/png',
          'etag': '"v1"',
        });
      }
      expect(headers?['if-none-match'], '"v1"');
      return http.Response('', 304);
    }

    final store = MarkdownNetworkImageStore(
      cacheDir: cacheDir,
      httpGet: get,
      // Force revalidate even when memory/disk warm.
      revalidateOnLoad: true,
    );
    await store.load('https://example.com/a.png');
    store.clearMemory();
    final again = await store.load('https://example.com/a.png');
    expect(again, isNotNull);
    expect(again!.bytes, pngBytes);
    expect(fetches, 2);
    expect(lastHeaders?['if-none-match'], '"v1"');
  });

  test('prefetch loads urls through the store', () async {
    final seen = <String>{};
    final store = MarkdownNetworkImageStore(
      cacheDir: cacheDir,
      maxConcurrent: 3,
      httpGet: (uri, {headers}) async {
        seen.add(uri.toString());
        return http.Response.bytes(pngBytes, 200);
      },
    );
    await store.prefetch([
      'https://example.com/1.png',
      'https://example.com/2.png',
    ]);
    expect(seen, containsAll(['https://example.com/1.png', 'https://example.com/2.png']));
    expect(await store.load('https://example.com/1.png'), isNotNull);
  });
}
