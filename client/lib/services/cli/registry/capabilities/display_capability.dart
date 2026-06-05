import '../../../../l10n/app_localizations.dart';
import '../cli_capability.dart';

abstract interface class DisplayCapability implements CliCapability {
  String label(AppLocalizations l10n);
}
