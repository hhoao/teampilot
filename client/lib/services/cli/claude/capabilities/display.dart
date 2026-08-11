import '../../../../l10n/app_localizations.dart';
import '../../registry/capabilities/display_capability.dart';

final class ClaudeDisplay implements DisplayCapability {
  const ClaudeDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolClaude;
}
