import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('cursor pushes the bus protocol with a flat stdout payload', () {
    final cap = registry.capability<HookCapability>(CliTool.cursor)!;
    expect(cap.pushesBusProtocol, isTrue);
    expect(
      jsonEncode(cap.sessionStartStdoutPayload(additionalContext: 'ctx')),
      '{"additional_context":"ctx"}',
    );
  });

  test('other hook writers use the claude-family payload', () {
    for (final cli in CliTool.values) {
      if (cli == CliTool.cursor) continue;
      final cap = registry.capability<HookCapability>(cli)!;
      expect(cap.pushesBusProtocol, isFalse, reason: 'cli=$cli');
      expect(
        jsonEncode(cap.sessionStartStdoutPayload(additionalContext: 'ctx')),
        '{"hookSpecificOutput":{"hookEventName":"SessionStart",'
        '"additionalContext":"ctx"}}',
        reason: 'cli=$cli',
      );
    }
  });
}
