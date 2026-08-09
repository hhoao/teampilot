import '../../../models/team_config.dart';
import '../../../services/cli/claude/claude_bootstrap_entry.dart';
import '../../../services/cli/claude/provider/claude_provider_credential_capability.dart';
import '../../../services/cli/codex/codex_bootstrap_entry.dart';
import '../../../services/cli/codex/provider/codex_provider_credential_capability.dart';
import '../../../services/cli/cursor/cursor_bootstrap_entry.dart';
import '../../../services/cli/cursor/provider/cursor_provider_credential_capability.dart';
import '../../../services/cli/cursor/provider/cursor_provider_model_capability.dart';
import '../../../services/cli/opencode/opencode_bootstrap_entry.dart';
import '../../../services/cli/opencode/provider/opencode_provider_credential_capability.dart';
import 'capabilities/member_agent_preset_capability.dart';
import 'capabilities/member_config_inspection_capability.dart';
import 'capabilities/provider_model_capability.dart';
import 'cli_bootstrap.dart';
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
  final opencodeEntry = bootstrap.entry<OpencodeBootstrapEntry>(CliTool.opencode);
  final cursorEntry = bootstrap.entry<CursorBootstrapEntry>(CliTool.cursor);

  registry.register(
    ClaudeCliTool(
      providerCredential: ClaudeProviderCredentialCapability(
        credentials: claudeEntry?.credentialsService,
      ),
    ),
  );
  registry.register(
    CodexCliTool(
      providerCredential: CodexProviderCredentialCapability(
        credentials: codexEntry?.credentialsService,
      ),
    ),
  );
  registry.register(
    OpencodeCliTool(
      providerCredential: OpencodeProviderCredentialCapability(
        credentials: opencodeEntry?.credentialsService,
      ),
    ),
  );
  registry.register(
    CursorCliTool(
      providerModel: CursorProviderModelCapability(
        modelsService: cursorEntry?.agentModelsService,
      ),
      providerCredential: CursorProviderCredentialCapability(
        credentials: cursorEntry?.credentialsService,
      ),
    ),
  );

  registry.register(const FlashskyaiCliTool());

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
      (cli) => registry.capability<ProviderModelCapability>(cli) != null,
    ),
    'Every CliTool must register ProviderModelCapability',
  );
  assert(
    CliTool.values.every(
      (cli) =>
          registry.capability<MemberConfigInspectionCapability>(cli) != null,
    ),
    'Every CliTool must register MemberConfigInspectionCapability',
  );
  _verifyNativeTeamRegistration(registry);
  _verifyMemberAgentPresetRegistration(registry);
}

void _verifyMemberAgentPresetRegistration(CliToolRegistry registry) {
  const allowed = {CliTool.claude, CliTool.flashskyai};
  final presetIds = {
    for (final def in registry.withCapability<MemberAgentPresetCapability>())
      def.id,
  };
  if (presetIds.length != allowed.length ||
      !allowed.every(presetIds.contains)) {
    throw StateError(
      'Member agent preset is limited to CLIs with MemberAgentPresetCapability; '
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
      'Native team mode is limited to CLIs with NativeTeamCapability; '
      'got ${nativeIds.map((c) => c.value).join(', ')}',
    );
  }
}
