import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_http.dart';
import 'package:teampilot/services/remote_download/remote_download_resolver.dart';
import 'package:teampilot/services/remote_download/remote_download_source.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

RemoteDownloadResolver _resolverWithMirror() {
  return RemoteDownloadResolver(
    RemoteDownloadCatalog([
      const RemoteDownloadSource(
        id: 'github-official',
        priority: 10,
        enabled: true,
        matchHosts: ['api.github.com'],
      ),
      const RemoteDownloadSource(
        id: 'mirror',
        priority: 20,
        enabled: true,
        matchHosts: ['api.github.com'],
        rewriteOrigin: 'https://mirror.example',
      ),
    ]),
  );
}

void main() {
  group('RemoteDownloadHttp', () {
    test('get tries next candidate after non-200', () async {
      final fake = _FakeClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response('error', 500);
        }
        if (request.url.host == 'mirror.example') {
          return http.Response('ok', 200);
        }
        return http.Response('not found', 404);
      });
      final httpLayer = RemoteDownloadHttp(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      final res = await httpLayer.get(
        Uri.parse('https://api.github.com/repos/o/r/releases/latest'),
        headers: {'User-Agent': 'test'},
      );
      expect(res.statusCode, 200);
      expect(res.body, 'ok');
    });

    test('head tries next candidate after non-200', () async {
      final fake = _FakeClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response('', 503);
        }
        if (request.url.host == 'mirror.example') {
          return http.Response('', 200, headers: {'content-length': '42'});
        }
        return http.Response('', 404);
      });
      final httpLayer = RemoteDownloadHttp(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      final res = await httpLayer.head(
        Uri.parse('https://api.github.com/repos/o/r/releases/latest'),
        headers: {'User-Agent': 'test'},
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-length'], '42');
    });

    test('send returns redirect after first host network failure', () async {
      final fake = _FakeClient((request) async {
        if (request.url.host == 'api.github.com') {
          throw const SocketException('connection refused');
        }
        if (request.url.host == 'mirror.example') {
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://github.com/o/r/releases/tag/v1.0.0',
            },
          );
        }
        return http.Response('not found', 404);
      });
      final httpLayer = RemoteDownloadHttp(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      final streamed = await httpLayer.send(
        (uri) => http.Request('GET', uri)..followRedirects = false,
        Uri.parse('https://api.github.com/repos/o/r/releases/latest'),
      );
      expect(streamed.statusCode, 302);
      expect(streamed.headers['location'], contains('/releases/tag/'));
    });

    test('send returns first completed response regardless of status', () async {
      final fake = _FakeClient((request) async {
        return http.Response('rate limit', 403);
      });
      final httpLayer = RemoteDownloadHttp(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      final streamed = await httpLayer.send(
        (uri) => http.Request('GET', uri)..followRedirects = false,
        Uri.parse('https://api.github.com/repos/o/r/releases/latest'),
      );
      expect(streamed.statusCode, 403);
    });

    test('throws RemoteDownloadException when all get candidates fail', () async {
      final fake = _FakeClient((request) async {
        return http.Response('error', 500);
      });
      final httpLayer = RemoteDownloadHttp(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      await expectLater(
        httpLayer.get(
          Uri.parse('https://api.github.com/repos/o/r/releases/latest'),
        ),
        throwsA(
          isA<RemoteDownloadException>().having(
            (e) => e.attempts.length,
            'attempt count',
            2,
          ),
        ),
      );
    });
  });
}
