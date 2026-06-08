import '../../../models/team_config.dart';
import '../../../services/provider/claude/claude_provider_credential_capability.dart';
import '../../../services/provider/codex/codex_provider_credential_capability.dart';
import '../../../services/provider/cursor/cursor_provider_credential_capability.dart';
import '../../../services/provider/cursor/cursor_provider_model_capability.dart';
import '../../../services/provider/opencode/opencode_provider_credential_capability.dart';
import 'cli_bootstrap.dart';
import 'cli_tool_registry.dart';
import 'tools/claude_cli_tool.dart';
import 'tools/codex_cli_tool.dart';
import 'tools/cursor_cli_tool.dart';
import 'tools/flashskyai_cli_tool.dart';
import 'capabilities/provider_model_capability.dart';
import 'tools/opencode_cli_tool.dart';

void registerBuiltInCliTools(
  CliToolRegistry registry, {
  CliBootstrap bootstrap = const CliBootstrap(),
}) {
  registry.register(const FlashskyaiCliTool());
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
}
