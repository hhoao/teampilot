import '../../../../l10n/app_localizations.dart';
import '../../registry/capabilities/display_capability.dart';

final class FlashskyaiDisplay implements DisplayCapability {
  const FlashskyaiDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolFlashskyai;
}
