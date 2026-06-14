import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/member_config_inspection_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every CLI registers a MemberConfigInspectionCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      expect(
        registry.capability<MemberConfigInspectionCapability>(cli),
        isNotNull,
        reason: 'missing inspection capability for ${cli.value}',
      );
    }
  });
}
