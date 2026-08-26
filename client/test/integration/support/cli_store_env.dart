/// Strips TeamPilot-injected CLI store redirects from environments handed to
/// integration PTY probes.
///
/// Live TeamPilot sessions isolate each CLI's data/config stores via
/// environment variables (`OPENCODE_DB`, `CLAUDE_CONFIG_DIR`, …). Integration
/// tests are frequently launched from inside those PTYs, so a probe that
/// inherits the parent environment boots the real CLI against the *production*
/// session store — e.g. an opencode TUI probe minting `ses_*` rows in the
/// session's live `opencode.db`, which then hijacks newest-root resume
/// detection and makes the chat history disappear.
library;

/// Environment variables TeamPilot injects to redirect CLI stores.
///
/// Keep in sync with `client/lib/services/cli/**/capabilities/*` launch env:
/// - `OPENCODE_DB` / `OPENCODE_CONFIG_DIR` (opencode session isolation)
/// - `XDG_DATA_HOME` (opencode provider credentials + global data dir)
/// - `CLAUDE_CONFIG_DIR` / `TEAMPILOT_CLAUDE_SETTINGS_FILE` (claude)
/// - `CODEX_HOME` (codex)
/// - `CURSOR_CONFIG_DIR` (cursor-agent)
/// - `FLASHSKYAI_CONFIG_DIR` / `FLASHSKYAI_SESSION_HOME_DIR` /
///   `LLM_CONFIG_PATH` (flashskyai)
const cliStoreEnvKeys = <String>{
  'OPENCODE_DB',
  'OPENCODE_CONFIG_DIR',
  'XDG_DATA_HOME',
  'CLAUDE_CONFIG_DIR',
  'TEAMPILOT_CLAUDE_SETTINGS_FILE',
  'CODEX_HOME',
  'CURSOR_CONFIG_DIR',
  'FLASHSKYAI_CONFIG_DIR',
  'FLASHSKYAI_SESSION_HOME_DIR',
  'LLM_CONFIG_PATH',
};

/// Returns [environment] without [cliStoreEnvKeys], so probes resolve CLI
/// stores from machine defaults instead of a live TeamPilot session.
Map<String, String> sanitizeCliStoreEnvironment(Map<String, String> environment) {
  final sanitized = Map<String, String>.of(environment);
  sanitized.removeWhere((key, _) => cliStoreEnvKeys.contains(key));
  return sanitized;
}
