import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/launch/layered_config_bundle.dart';

void main() {
  test('merge hookIds team > expert > workspace with dedupe', () {
    final merged = LayeredConfigBundle.merge(
      team: const ConfigBundle(hookIds: ['h-team', 'h-shared']),
      expert: const ConfigBundle(hookIds: ['h-exp', 'h-shared']),
      workspace: const ConfigBundle(hookIds: ['h-ws', 'h-shared']),
    );
    expect(merged.hookIds, ['h-team', 'h-shared', 'h-exp', 'h-ws']);
  });

  test('empty layers fall back to workspace', () {
    final merged = LayeredConfigBundle.merge(
      workspace: const ConfigBundle(hookIds: ['h-ws']),
    );
    expect(merged.hookIds, ['h-ws']);
  });

  test('hookIds round-trip through toJson/fromJson', () {
    const bundle = ConfigBundle(
      skillIds: ['s1'],
      hookIds: ['h1', 'h2'],
    );
    final restored = ConfigBundle.fromJson(bundle.toJson());
    expect(restored, bundle);
  });
}
