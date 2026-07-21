import 'package:teampilot/services/terminal/terminal_session.dart';

import 'cli_test_profile_claude_boot.dart';

/// FlashskyAI shares Claude Code's Ink composer (`❯`) and trust / API-key
/// gates — reuse the Claude boot helpers until an L2 probe proves otherwise.
Future<void> dismissFlashskyaiBootGates(TerminalSession session) =>
    dismissClaudeBootGates(session);

Future<bool> bootFlashskyaiToPrompt(TerminalSession session) =>
    bootClaudeToPrompt(session);
