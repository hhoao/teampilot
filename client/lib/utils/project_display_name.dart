import '../l10n/app_localizations.dart';
import '../models/app_project.dart';

extension AppProjectLocalizedName on AppProject {
  /// Localized name shown in the UI. The built-in personal project
  /// ([isDefaultPersonal]) renders a localized label ("单人对话" / "Solo chat")
  /// instead of its on-disk folder name, unless the user has given it an
  /// explicit [display]. All other projects fall back to [effectiveDisplay].
  String localizedName(AppLocalizations l10n) {
    if (isDefaultPersonal && display.isEmpty) {
      return l10n.homeWorkspaceDefaultPersonalProjectName;
    }
    return effectiveDisplay;
  }
}
