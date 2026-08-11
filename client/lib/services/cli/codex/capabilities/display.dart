import '../../../../l10n/app_localizations.dart';
import '../../registry/capabilities/display_capability.dart';

final class CodexDisplay implements DisplayCapability {
  const CodexDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolCodex;
}
