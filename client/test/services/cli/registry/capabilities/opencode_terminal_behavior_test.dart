import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/built_in_tool_capabilities.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  group('OpencodeTerminalBehavior', () {
    test('uses full-screen inject like other TUI CLIs', () {
      const behavior = OpencodeTerminalBehavior();

      expect(behavior.usesFullScreenInput, isTrue);
      expect(behavior.usesGridPasteAck, isTrue);
      expect(
        behavior.pathDropBehavior.mode,
        TerminalPathDropMode.bracketedNoSubmit,
      );
    });

    test('CliToolRegistry exposes full-screen behavior for opencode', () {
      final behavior = CliToolRegistry.builtIn()
          .capability<TerminalBehaviorCapability>(CliTool.opencode);

      expect(behavior, isNotNull);
      expect(behavior!.usesFullScreenInput, isTrue);
    });
  });
}
