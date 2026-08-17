import '../../../models/team_config.dart';
import '../../../services/cli/claude/claude_bootstrap_entry.dart';
import '../../../services/cli/codex/codex_bootstrap_entry.dart';
import '../../../services/cli/cursor/cursor_bootstrap_entry.dart';
import '../../../services/cli/opencode/opencode_bootstrap_entry.dart';
import 'capabilities/member_config_inspection_capability.dart';
import '../../../services/cli/claude/capabilities/provider.dart';
import '../../../services/cli/codex/capabilities/provider.dart';
import '../../../services/cli/cursor/capabilities/provider.dart';
import '../../../services/cli/opencode/capabilities/provider.dart';
import 'capabilities/provider_capability.dart';
import 'capabilities/cli_session_capability.dart';
import 'capabilities/team_behavior_capability.dart';
import 'capabilities/cli_executable_capability.dart';
import 'capabilities/chat_interaction_capability.dart';
import 'capabilities/terminal_behavior_capability.dart';
import 'capabilities/plugin_capability.dart';
import 'cli_bootstrap.dart';
import 'cli_capability.dart';
import 'cli_tool_registry.dart';
import '../claude/claude_tool.dart';
import '../codex/codex_tool.dart';
import '../cursor/cursor_tool.dart';
import '../flashskyai/flashskyai_tool.dart';
import '../opencode/opencode_tool.dart';

void registerBuiltInCliTools(
  CliToolRegistry registry, {
  CliBootstrap bootstrap = const CliBootstrap({}),
}) {
  final claudeEntry = bootstrap.entry<ClaudeBootstrapEntry>(CliTool.claude);
  final codexEntry = bootstrap.entry<CodexBootstrapEntry>(CliTool.codex);
  final opencodeEntry = bootstrap.entry<OpencodeBootstrapEntry>(
    CliTool.opencode,
  );
  final cursorEntry = bootstrap.entry<CursorBootstrapEntry>(CliTool.cursor);

  registry.register(
    ClaudeCliTool(
      provider: ClaudeProviderCapability(
        modelsService: claudeEntry?.modelsService,
        credentials: claudeEntry?.credentialsService,
      ),
    ),
  );
  registry.register(
    CodexCliTool(
      provider: CodexProviderCapability(
        modelsService: codexEntry?.modelsService,
        credentials: codexEntry?.credentialsService,
      ),
    ),
  );
  registry.register(
    OpencodeCliTool(
      provider: OpencodeProviderCapability(
        modelsService: opencodeEntry?.modelsService,
        credentials: opencodeEntry?.credentialsService,
      ),
    ),
  );
  registry.register(
    CursorCliTool(
      provider: CursorProviderCapability(
        modelsService: cursorEntry?.agentModelsService,
        credentials: cursorEntry?.credentialsService,
      ),
    ),
  );

  registry.register(
    FlashskyaiCliTool(),
  );

  assert(
    CliTool.values.every((cli) => registry.tryGet(cli) != null),
    'Every CliTool must have a registered definition',
  );
  assert(
    registry.all.length == CliTool.values.length,
    'Registry must not contain extra definitions beyond CliTool.values',
  );
  assert(
    CliTool.values.every(
      (cli) => registry.capability<ProviderCapability>(cli) != null,
    ),
    'Every CliTool must register ProviderCapability',
  );
  assert(
    CliTool.values.every(
      (cli) =>
          registry.capability<MemberConfigInspectionCapability>(cli) != null,
    ),
    'Every CliTool must register MemberConfigInspectionCapability',
  );
  _verifyRequired<CliSessionCapability>(registry);
  _verifyRequired<TeamBehaviorCapability>(registry);
  _verifyRequired<CliExecutableCapability>(registry);
  _verifyRequired<TerminalBehaviorCapability>(registry);
  _verifyRequired<PluginCapability>(registry);
  _verifyRequired<ChatInteractionCapability>(registry);
  _verifyNativeTeamRegistration(registry);
  _verifyMemberAgentPresetRegistration(registry);
}

void _verifyRequired<T extends CliCapability>(CliToolRegistry registry) {
  assert(
    CliTool.values.every((cli) => registry.capability<T>(cli) != null),
    'Every CliTool must register ${T.toString()}',
  );
}

void _verifyMemberAgentPresetRegistration(CliToolRegistry registry) {
  const allowed = {CliTool.claude, CliTool.flashskyai};
  final presetIds = {
    for (final def
        in registry.all.where((d) => registry.memberAgentPresetStyle(d.id) != null))
      def.id,
  };
  if (presetIds.length != allowed.length ||
      !allowed.every(presetIds.contains)) {
    throw StateError(
      'Member agent preset is limited to CLIs exposing an agent preset '
      'style via TeamBehaviorCapability; '
      'got ${presetIds.map((c) => c.value).join(', ')}',
    );
  }
}

void _verifyNativeTeamRegistration(CliToolRegistry registry) {
  const allowed = {CliTool.claude, CliTool.flashskyai};
  final nativeIds = {for (final def in registry.nativeTeamLaunchable) def.id};
  if (nativeIds.length != allowed.length ||
      !allowed.every(nativeIds.contains)) {
    throw StateError(
      'Native team mode is limited to CLIs exposing native team support via '
      'TeamBehaviorCapability; '
      'got ${nativeIds.map((c) => c.value).join(', ')}',
    );
  }
}
