import '../../l10n/app_localizations.dart';
import '../../models/launch_profile.dart';
import '../../models/team_config.dart';
import '../../services/storage/launch_profile_provisioner.dart';

/// User-visible name for a built-in team identity, if [teamId] is provisioned.
String? builtInTeamDisplayName(AppLocalizations l10n, String teamId) {
  return switch (teamId) {
    LaunchProfileProvisioner.defaultNativeTeamId =>
      l10n.homeWorkspaceDefaultNativeTeamName,
    LaunchProfileProvisioner.defaultMixedTeamId =>
      l10n.homeWorkspaceDefaultMixedTeamName,
    _ => null,
  };
}

/// User-visible name for a launch identity. Built-in defaults use l10n instead
/// of the persisted English `display` / `name` fields.
String launchProfileDisplayName(AppLocalizations l10n, LaunchProfile profile) {
  if (profile is TeamProfile) {
    final builtIn = builtInTeamDisplayName(l10n, profile.id);
    if (builtIn != null) return builtIn;
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
