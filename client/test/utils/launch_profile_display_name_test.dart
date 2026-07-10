import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/launch_profile_display_name.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('built-in team ids use l10n names', () {
    final native = TeamProfile(
      id: LaunchProfileProvisioner.defaultNativeTeamId,
      name: 'Native',
    );
    expect(
      launchProfileDisplayName(l10n, native),
      l10n.homeWorkspaceDefaultNativeTeamName,
    );
  });

  test('custom team uses persisted name', () {
    final team = TeamProfile(id: 'custom', name: 'My Team');
    expect(launchProfileDisplayName(l10n, team), 'My Team');
  });
}
