import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/workspace_project_config.dart';

void main() {
  test('round-trips bundle and extension overrides', () {
    const config = WorkspaceProjectConfig(
      bundle: ConfigBundle(
        skillIds: ['s1'],
        pluginIds: ['p1'],
        mcpServerIds: ['m1'],
      ),
      extensionOverrides: {'rtk': false},
    );
    final restored = WorkspaceProjectConfig.fromJson(config.toJson());
    expect(restored, config);
  });

  test('effectiveExtensionEnabled honors override then global', () {
    const config = WorkspaceProjectConfig(extensionOverrides: {'rtk': false});
    expect(
      config.effectiveExtensionEnabled(
        extensionId: 'rtk',
        globalEnabled: {'rtk', 'codegraph'},
      ),
      isFalse,
    );
    expect(
      config.effectiveExtensionEnabled(
        extensionId: 'codegraph',
        globalEnabled: {'rtk', 'codegraph'},
      ),
      isTrue,
    );
  });
}
