import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('only dual-transport CLIs let the user choose', () {
    final choosable = {
      for (final cli in CliTool.values)
        if (registry.capability<CliTransportCapability>(cli)!.canChooseTransport)
          cli,
    };
    expect(choosable, {
      CliTool.claude,
      CliTool.cursor,
      CliTool.codex,
      CliTool.opencode,
    });
  });

  test('canChooseTransport equals pty && acp', () {
    for (final cli in CliTool.values) {
      final transport = registry.capability<CliTransportCapability>(cli)!;
      expect(
        transport.canChooseTransport,
        transport.supports(CliTransport.pty) &&
            transport.supports(CliTransport.acp),
        reason: 'cli=$cli',
      );
    }
  });
}
