import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_resolver.dart';
import 'package:teampilot/services/remote_download/remote_download_source.dart';

void main() {
  test('identity source returns original uri', () {
    final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
    final uri = Uri.parse('https://api.github.com/repos/a/b/releases/latest');
    final c = resolver.resolve(uri);
    expect(c, hasLength(1));
    expect(c.single.uri, uri);
    expect(c.single.sourceId, 'github-official');
  });

  test('mirror rewrite keeps path and query', () {
    final catalog = RemoteDownloadCatalog([
      const RemoteDownloadSource(
        id: 'github-official',
        priority: 10,
        enabled: true,
        matchHosts: ['github.com'],
      ),
      const RemoteDownloadSource(
        id: 'mirror',
        priority: 20,
        enabled: true,
        matchHosts: ['github.com'],
        rewriteOrigin: 'https://mirror.example',
      ),
    ]);
    final resolver = RemoteDownloadResolver(catalog);
    final c = resolver.resolve(
      Uri.parse('https://github.com/o/r/releases/download/v1/a.apk?x=1'),
    );
    expect(c.map((e) => e.uri.toString()).toList(), [
      'https://github.com/o/r/releases/download/v1/a.apk?x=1',
      'https://mirror.example/o/r/releases/download/v1/a.apk?x=1',
    ]);
  });

  test('unmatched host returns single passthrough candidate', () {
    final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
    final uri = Uri.parse('https://example.com/file.bin');
    final c = resolver.resolve(uri);
    expect(c, hasLength(1));
    expect(c.single.sourceId, 'passthrough');
    expect(c.single.uri, uri);
  });

  test('withProvider re-reads catalog on each resolve', () {
    var callCount = 0;
    final resolver = RemoteDownloadResolver.withProvider(() {
      callCount++;
      if (callCount == 1) {
        return RemoteDownloadCatalog.defaults();
      }
      return RemoteDownloadCatalog([
        const RemoteDownloadSource(
          id: 'mirror',
          priority: 10,
          enabled: true,
          matchHosts: ['github.com'],
          rewriteOrigin: 'https://mirror.example',
        ),
      ]);
    });

    final uri = Uri.parse('https://github.com/o/r/releases/download/v1/a.apk');

    final first = resolver.resolve(uri);
    expect(first, hasLength(1));
    expect(first.single.sourceId, 'github-official');
    expect(first.single.uri, uri);

    final second = resolver.resolve(uri);
    expect(second, hasLength(1));
    expect(second.single.sourceId, 'mirror');
    expect(
      second.single.uri.toString(),
      'https://mirror.example/o/r/releases/download/v1/a.apk',
    );
  });
}
