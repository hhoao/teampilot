import 'package:flutter/foundation.dart';

import '../claude/provider/claude_provider_credentials_service.dart';
import '../codex/provider/codex_provider_credentials_service.dart';
import '../cursor/provider/cursor_agent_models_service.dart';
import '../cursor/provider/cursor_provider_credentials_service.dart';
import '../opencode/provider/opencode_provider_credentials_service.dart';

/// Runtime services wired into [CliToolRegistry] after [AppStorage] is ready.
///
/// Extend when another CLI needs injected catalogs (live model lists, agents, …).
@immutable
class CliBootstrap {
  const CliBootstrap({
    this.cursorAgentModelsService,
    this.claudeCredentialsService,
    this.cursorCredentialsService,
    this.codexCredentialsService,
    this.opencodeCredentialsService,
  });

  final CursorAgentModelsService? cursorAgentModelsService;
  final ClaudeProviderCredentialsService? claudeCredentialsService;
  final CursorProviderCredentialsService? cursorCredentialsService;
  final CodexProviderCredentialsService? codexCredentialsService;
  final OpencodeProviderCredentialsService? opencodeCredentialsService;
}
