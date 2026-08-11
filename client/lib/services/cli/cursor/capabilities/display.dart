import '../../../../l10n/app_localizations.dart';
import '../../registry/capabilities/display_capability.dart';

final class CursorDisplay implements DisplayCapability {
  const CursorDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolCursor;
}
