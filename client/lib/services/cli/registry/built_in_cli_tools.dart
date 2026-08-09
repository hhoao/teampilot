import '../../../models/team_config.dart';
import '../../../services/cli/claude/provider/claude_provider_credential_capability.dart';
import '../../../services/cli/codex/provider/codex_provider_credential_capability.dart';
import '../../../services/cli/cursor/provider/cursor_provider_credential_capability.dart';
import '../../../services/cli/cursor/provider/cursor_provider_model_capability.dart';
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
  CliBootstrap bootstrap = const CliBootstrap(),
}) {
  registry.register(
    ClaudeCliTool(
      providerCredential: ClaudeProviderCredentialCapability(
        credentials: bootstrap.claudeCredentialsService,
      ),
    ),
  );
  registry.register(
    CodexCliTool(
      providerCredential: CodexProviderCredentialCapability(
        credentials: bootstrap.codexCredentialsService,
      ),
    ),
  );
  registry.register(
    OpencodeCliTool(
      providerCredential: OpencodeProviderCredentialCapability(
        credentials: bootstrap.opencodeCredentialsService,
      ),
    ),
  );
  registry.register(
    CursorCliTool(
      providerModel: CursorProviderModelCapability(
        modelsService: bootstrap.cursorAgentModelsService,
      ),
      providerCredential: CursorProviderCredentialCapability(
        credentials: bootstrap.cursorCredentialsService,
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
