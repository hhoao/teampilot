import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';

void main() {
  test('built-in manifests include a valid rtk manifest', () {
    final manifests = builtInExtensionManifests();
    final rtk = manifests.firstWhere((m) => m.id == 'rtk');

    expect(rtk.detect.executable, 'rtk');
    expect(rtk.detect.minVersion, '0.23.0');
    expect(rtk.detect.requires, contains('jq'));

    final hook = rtk.effects.firstWhere((e) => e.kind == 'settings-hook');
    expect(hook.hookEvent, 'PreToolUse');
    expect(hook.hookMatcher, 'Bash');
    expect(hook.scriptAsset, 'rtk-rewrite');
    expect(hook.marker, 'rtk-rewrite');
    expect(hook.appliesTo, containsAll(['claude', 'flashskyai']));
  });
}
