import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('native team launchable excludes non-native clis like codex', () {
    final registry = CliToolRegistry.builtIn();
    final nativeIds = {
      for (final definition in registry.nativeTeamLaunchable) definition.id,
    };

    expect(nativeIds, contains(CliTool.claude));
    expect(nativeIds, isNot(contains(CliTool.codex)));
    expect(nativeIds, isNot(contains(CliTool.cursor)));
  });

  test('generator may use any launchable cli even when native team is locked', () {
    final registry = CliToolRegistry.builtIn();
    final launchable = {
      for (final definition in registry.launchable) definition.id,
    };
    final native = {
      for (final definition in registry.nativeTeamLaunchable) definition.id,
    };

    // Product rule: pool is native-filtered; generator is not.
    expect(launchable.difference(native), isNotEmpty);
    expect(launchable, contains(CliTool.codex));
  });
}
