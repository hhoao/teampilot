import 'package:flutter/foundation.dart';

import '../../provider/claude/claude_provider_credentials_service.dart';
import '../../provider/codex/codex_provider_credentials_service.dart';
import '../../provider/cursor/cursor_agent_models_service.dart';
import '../../provider/cursor/cursor_provider_credentials_service.dart';
import '../../provider/opencode/opencode_provider_credentials_service.dart';

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
