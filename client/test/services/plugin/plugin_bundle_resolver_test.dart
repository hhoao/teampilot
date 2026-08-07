import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/plugin/plugin_bundle_resolver.dart';

Plugin _plugin(String id, {String? directory}) => Plugin(
  id: id,
  name: id.split('/').last,
  description: '',
  version: '1.0.0',
  directory: directory ?? id.replaceAll('/', '__'),
  capabilities: const PluginCapabilities(),
  installedAt: 0,
  updatedAt: 0,
);

void main() {
  group('PluginBundleResolver.resolve', () {
    test('resolves installed ids in enable-list order (deduplicated)', () {
      final catalog = [_plugin('a/m/p1'), _plugin('b/m/p2')];

      final result = PluginBundleResolver.resolve(
        enabledPluginIds: ['b/m/p2', 'a/m/p1', 'b/m/p2'],
        installedCatalog: catalog,
      );

      expect(result.enabled.map((p) => p.id), ['b/m/p2', 'a/m/p1']);
      expect(result.skippedMissingIds, isEmpty);
    });

    test('drops unknown / not-installed ids into skippedMissingIds', () {
      final catalog = [_plugin('a/m/p1')];

      final result = PluginBundleResolver.resolve(
        enabledPluginIds: ['a/m/p1', 'missing/plugin/x'],
        installedCatalog: catalog,
      );

      expect(result.enabled.map((p) => p.id), ['a/m/p1']);
      expect(result.skippedMissingIds, ['missing/plugin/x']);
    });

    test('empty enable list yields nothing', () {
      final result = PluginBundleResolver.resolve(
        enabledPluginIds: const [],
        installedCatalog: [_plugin('a/m/p1')],
      );

      expect(result.enabled, isEmpty);
      expect(result.skippedMissingIds, isEmpty);
    });

    test('trims whitespace and ignores empty ids', () {
      final catalog = [_plugin('a/m/p1')];

      final result = PluginBundleResolver.resolve(
        enabledPluginIds: ['  a/m/p1  ', '   ', ''],
        installedCatalog: catalog,
      );

      expect(result.enabled.map((p) => p.id), ['a/m/p1']);
      expect(result.skippedMissingIds, isEmpty);
    });
  });
}
