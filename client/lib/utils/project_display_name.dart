import '../l10n/app_localizations.dart';
import '../models/app_project.dart';

extension AppProjectLocalizedName on AppProject {
  /// Localized name shown in the UI. Falls back to [effectiveDisplay].
  String localizedName(AppLocalizations l10n) => effectiveDisplay;
}
