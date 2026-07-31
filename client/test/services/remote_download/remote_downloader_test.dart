import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_http.dart';
import 'package:teampilot/services/remote_download/remote_download_resolver.dart';
import 'package:teampilot/services/remote_download/remote_download_source.dart';
import 'package:teampilot/services/remote_download/remote_downloader.dart';

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
      contentLength: response.bodyBytes.length,
      request: request,
    );
  }
}

class _StreamingFakeClient extends http.BaseClient {
  _StreamingFakeClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
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
  group('RemoteDownloader', () {
    test('fetch succeeds on second candidate', () async {
      final fake = _FakeClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response('error', 500);
        }
        if (request.url.host == 'mirror.example') {
          return http.Response(
            'binary-content',
            200,
            headers: {'content-length': '14'},
          );
        }
        return http.Response('not found', 404);
      });
      final downloader = RemoteDownloader(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      final file = await downloader.fetch(
        Uri.parse('https://api.github.com/repos/o/r/releases/download/v1/a.apk'),
        destFileName: 'a.apk',
        tempRoot: Directory.systemTemp,
      );
      expect(file.path, endsWith('a.apk'));
      expect(await file.readAsString(), 'binary-content');
      await file.parent.delete(recursive: true);
    });

    test('sha256 mismatch skips candidate', () async {
      const goodData = 'good-apk-content';
      const badData = 'bad-content';
      final goodHash = sha256.convert(utf8.encode(goodData)).toString();
      var requestCount = 0;
      final fake = _FakeClient((request) async {
        requestCount++;
        if (request.url.host == 'api.github.com') {
          return http.Response(
            badData,
            200,
            headers: {'content-length': '${badData.length}'},
          );
        }
        return http.Response(
          goodData,
          200,
          headers: {'content-length': '${goodData.length}'},
        );
      });
      final downloader = RemoteDownloader(
        client: fake,
        resolver: _resolverWithMirror(),
      );
      final file = await downloader.fetch(
        Uri.parse('https://api.github.com/repos/o/r/releases/download/v1/a.apk'),
        destFileName: 'test.apk',
        tempRoot: Directory.systemTemp,
        expectedSha256: goodHash,
      );
      expect(requestCount, 2);
      expect(await file.readAsString(), goodData);
      await file.parent.delete(recursive: true);
    });

    test('cancel stops mid-flight', () async {
      var cancelled = false;
      final fake = _StreamingFakeClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ]),
          200,
          contentLength: 9,
          request: request,
        );
      });
      final downloader = RemoteDownloader(
        client: fake,
        resolver: RemoteDownloadResolver(RemoteDownloadCatalog.defaults()),
      );
      await expectLater(
        downloader.fetch(
          Uri.parse('https://github.com/o/r/releases/download/v1/a.apk'),
          destFileName: 'a.apk',
          tempRoot: Directory.systemTemp,
          onProgress: (received, total) {
            if (received >= 3) {
              cancelled = true;
            }
          },
          isCancelled: () => cancelled,
        ),
        throwsA(isA<RemoteDownloadCancelledException>()),
      );
      expect(cancelled, isTrue);
    });
  });
}
