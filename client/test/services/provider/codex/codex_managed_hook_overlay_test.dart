import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/codex/codex_managed_hook_overlay.dart';

void main() {
  group('CodexManagedHookOverlay', () {
    test('enables hook network access in workspace-write sandbox', () {
      final toml = CodexManagedHookOverlay.build(
        dangerouslySkipPermissions: false,
      );
      expect(toml, contains('[sandbox_workspace_write]'));
      expect(toml, contains('network_access = true'));
      expect(toml, isNot(contains('danger-full-access')));
    });

    test('mirrors skip-permissions launch with danger-full-access', () {
      final toml = CodexManagedHookOverlay.build(
        dangerouslySkipPermissions: true,
      );
      expect(toml, contains('sandbox_mode = "danger-full-access"'));
      expect(toml, contains('network_access = true'));
    });
  });
}
