import '../l10n/app_localizations.dart';
import '../models/launch_profile.dart';
import '../models/personal_profile.dart';
import '../models/team_config.dart';
import '../services/storage/launch_profile_provisioner.dart';

/// User-visible name for a launch identity. Built-in defaults use l10n instead
/// of the persisted English `display` / `name` fields.
String launchProfileDisplayName(AppLocalizations l10n, LaunchProfile profile) {
  if (profile is PersonalProfile &&
      profile.id == LaunchProfileProvisioner.defaultPersonalId) {
    return l10n.homeWorkspaceDefaultPersonalWorkspaceName;
  }
  if (profile is TeamProfile &&
      profile.id == LaunchProfileProvisioner.defaultTeamId) {
    return l10n.homeWorkspaceDefaultTeamName;
  }
  return profile.display;
}

String? launchProfileDisplayNameForId(
  AppLocalizations l10n,
  Iterable<LaunchProfile> identities,
  String profileId,
) {
  final trimmed = profileId.trim();
  if (trimmed.isEmpty) return null;
  for (final identity in identities) {
    if (identity.id == trimmed) {
      return launchProfileDisplayName(l10n, identity);
    }
  }
  return null;
}
