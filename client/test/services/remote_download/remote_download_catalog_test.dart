import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_source.dart';

void main() {
  test('defaultCatalog has one enabled official github identity', () {
    final catalog = RemoteDownloadCatalog.defaults();
    expect(catalog.sources, hasLength(1));
    final s = catalog.sources.single;
    expect(s.id, 'github-official');
    expect(s.enabled, isTrue);
    expect(s.rewriteOrigin, isNull);
    expect(s.matchHosts, containsAll(['github.com', 'api.github.com']));
  });

  test('mergeOverrides replaces by id and keeps defaults for missing', () {
    final merged = RemoteDownloadCatalog.defaults().mergeOverrides([
      RemoteDownloadSource(
        id: 'github-official',
        priority: 10,
        enabled: false,
        matchHosts: const ['github.com', 'api.github.com'],
      ),
    ]);
    expect(merged.sources.single.enabled, isFalse);
  });
}
