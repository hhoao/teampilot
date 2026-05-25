import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-repo-svc-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('loads default marketplaces on first call', () async {
    final svc = PluginRepoService();
    final list = await svc.loadMarketplaces();
    expect(list, isNotEmpty);
    expect(
      File(p.join(tmp.path, 'plugins', 'marketplaces.json')).existsSync(),
      isTrue,
    );
  });

  test('addMarketplace / removeMarketplace / setEnabled', () async {
    final svc = PluginRepoService();
    await svc.loadMarketplaces();
    await svc.addMarketplace(const PluginMarketplace(owner: 'a', name: 'b'));
    var list = await svc.loadMarketplaces();
    expect(list.where((m) => m.owner == 'a' && m.name == 'b'), hasLength(1));

    await svc.setEnabled('a', 'b', false);
    list = await svc.loadMarketplaces();
    expect(list.firstWhere((m) => m.owner == 'a').enabled, isFalse);

    await svc.removeMarketplace('a', 'b');
    list = await svc.loadMarketplaces();
    expect(list.where((m) => m.owner == 'a' && m.name == 'b'), isEmpty);
  });

  test('addMarketplace is idempotent on owner/name', () async {
    final svc = PluginRepoService();
    await svc.loadMarketplaces();
    await svc.addMarketplace(const PluginMarketplace(owner: 'x', name: 'y'));
    await svc.addMarketplace(const PluginMarketplace(owner: 'x', name: 'y', branch: 'dev'));
    final list = await svc.loadMarketplaces();
    expect(list.where((m) => m.owner == 'x' && m.name == 'y'), hasLength(1));
  });
}
