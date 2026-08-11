import '../../../../l10n/app_localizations.dart';
import '../../registry/capabilities/display_capability.dart';

final class OpencodeDisplay implements DisplayCapability {
  const OpencodeDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolOpencode;
}
