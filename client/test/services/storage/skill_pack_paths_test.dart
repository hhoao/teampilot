import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  test('skill pack catalog cache path derives under the teampilot root', () {
    expect(
      AppPaths.skillPackCatalogCacheDirForTeampilotRoot(
        '/data/com.hhoa.teampilot',
      ),
      '/data/com.hhoa.teampilot/skill-packs/cache',
    );
  });

  test('skill pack catalog cache getter uses the app data root', () {
    const paths = AppPaths('/data/com.hhoa.teampilot');
    expect(
      paths.skillPackCatalogCacheDir,
      '/data/com.hhoa.teampilot/skill-packs/cache',
    );
  });
}
