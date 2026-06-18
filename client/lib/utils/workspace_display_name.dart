import '../l10n/app_localizations.dart';
import '../models/workspace.dart';

extension WorkspaceLocalizedName on Workspace {
  /// Localized name shown in the UI. Falls back to [effectiveDisplay].
  String localizedName(AppLocalizations l10n) => effectiveDisplay;
}
