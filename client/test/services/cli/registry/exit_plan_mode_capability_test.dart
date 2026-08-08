import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/exit_plan_mode_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('claude + flashskyai support in-chat approval', () {
    for (final cli in [CliTool.claude, CliTool.flashskyai]) {
      final cap = registry.capability<ExitPlanModeCapability>(cli);
      expect(cap, isNotNull);
      expect(cap!.supportsInChatApproval, isTrue);
      expect(cap.approvalKind, ExitPlanApprovalKind.hookReply);
    }
  });

  test('codex + opencode + cursor do not support in-chat approval', () {
    for (final cli in [CliTool.codex, CliTool.opencode, CliTool.cursor]) {
      final cap = registry.capability<ExitPlanModeCapability>(cli);
      expect(cap, isNotNull);
      expect(cap!.supportsInChatApproval, isFalse);
      expect(cap.approvalKind, ExitPlanApprovalKind.none);
    }
  });
}
