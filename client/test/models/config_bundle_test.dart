import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';

void main() {
  test('json round-trip preserves id lists', () {
    const bundle = ConfigBundle(
      skillIds: ['a', 'b'],
      pluginIds: ['p'],
      mcpServerIds: ['m'],
    );
    final restored = ConfigBundle.fromJson(bundle.toJson());
    expect(restored, bundle);
  });

  test('fromJson tolerates missing keys and trims/filters', () {
    final b = ConfigBundle.fromJson({'skillIds': [' x ', '']});
    expect(b.skillIds, ['x']);
    expect(b.pluginIds, isEmpty);
    expect(b.mcpServerIds, isEmpty);
  });

  test('toJson omits empty lists', () {
    expect(const ConfigBundle().toJson(), isEmpty);
  });
}
