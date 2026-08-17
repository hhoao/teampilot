import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test(
    'capabilitiesOf returns every matching capability in definition order',
    () {
      final first = MarkerCapability('first');
      final second = MarkerCapability('second');
      final registry = CliToolRegistry()
        ..register(FakeCliTool([first, OtherCapability(), second]));

      expect(registry.capabilitiesOf<MarkerCapability>(CliTool.claude), [
        first,
        second,
      ]);
      expect(
        registry.capability<MarkerCapability>(CliTool.claude),
        same(first),
      );
    },
  );

  test('capabilitiesOf returns an empty iterable for an unknown tool', () {
    final registry = CliToolRegistry();

    expect(registry.capabilitiesOf<MarkerCapability>(CliTool.claude), isEmpty);
  });
}

final class FakeCliTool implements CliToolDefinition {
  FakeCliTool(this.capabilities);

  @override
  final List<CliCapability> capabilities;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;
}

final class MarkerCapability implements CliCapability {
  MarkerCapability(this.name);

  final String name;
}

final class OtherCapability implements CliCapability {}
