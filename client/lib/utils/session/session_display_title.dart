import '../../l10n/app_localizations.dart';
import '../../models/app_session.dart';

/// Derives a sidebar title from the user's first submitted prompt.
String deriveSessionTitleFromFirstPrompt(String prompt, {int maxLength = 48}) {
  final firstLine = prompt
      .split(RegExp(r'[\r\n]+'))
      .first
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (firstLine.isEmpty) return '';

  if (firstLine.length <= maxLength) return firstLine;
  if (maxLength <= 1) return firstLine.substring(0, maxLength);
  return '${firstLine.substring(0, maxLength - 1)}…';
}

/// Sidebar / tab / dialog title from purpose + stored [display].
///
/// Team-generation builders keep an empty [AppSession.display] on purpose so
/// locale can switch; fall back to [AppLocalizations.teamGenerateBuilderTitle]
/// instead of the generic "New Chat" / "新对话".
String resolveSessionListTitle({
  required SessionPurpose purpose,
  required String display,
  required AppLocalizations l10n,
}) {
  if (purpose == SessionPurpose.teamGeneration) {
    final custom = display.trim();
    // Legacy English create-time fallback from the session port default.
    if (custom.isEmpty || custom == 'Team Builder') {
      return l10n.teamGenerateBuilderTitle;
    }
    return custom;
  }
  final trimmed = display.trim();
  return trimmed.isNotEmpty ? trimmed : l10n.defaultNewChatSessionTitle;
}

/// Sidebar / tab / dialog title for a session.
String sessionListDisplayTitle(AppSession session, AppLocalizations l10n) {
  return resolveSessionListTitle(
    purpose: session.purpose,
    display: session.display,
    l10n: l10n,
  );
}
