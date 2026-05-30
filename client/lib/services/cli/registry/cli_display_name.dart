import '../../../l10n/app_localizations.dart';
import 'cli_tool_definition.dart';

/// UI-only display name; uses [CliToolDefinition.id] as fallback.
String cliDisplayName(CliToolDefinition def, AppLocalizations l10n) =>
    switch (def.id) {
      'flashskyai' => l10n.appProviderToolFlashskyai,
      'claude' => l10n.appProviderToolClaude,
      'codex' => l10n.appProviderToolCodex,
      _ => def.id,
    };
