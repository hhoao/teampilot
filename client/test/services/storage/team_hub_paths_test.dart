import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  test('team-hub paths derive under the teampilot root', () {
    const root = '/data/com.hhoa.teampilot';
    expect(
      AppPaths.teamHubDirForTeampilotRoot(root),
      '/data/com.hhoa.teampilot/team-hub',
    );
    expect(
      AppPaths.teamHubCacheDirForTeampilotRoot(root),
      '/data/com.hhoa.teampilot/team-hub/cache',
    );
    expect(
      AppPaths.teamHubFavoritesJsonForTeampilotRoot(root),
      '/data/com.hhoa.teampilot/team-hub/favorites.json',
    );
  });
}
