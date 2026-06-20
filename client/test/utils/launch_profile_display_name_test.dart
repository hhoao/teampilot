import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/l10n/app_localizations_zh.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/launch_profile_display_name.dart';

void main() {
  test('built-in defaults use l10n labels', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    final personal = PersonalProfile(
      id: LaunchProfileProvisioner.defaultPersonalId,
      display: 'Personal',
    );
    final team = TeamProfile(
      id: LaunchProfileProvisioner.defaultTeamId,
      name: 'Default Team',
    );

    expect(launchProfileDisplayName(en, personal), 'Personal assistant');
    expect(launchProfileDisplayName(zh, personal), '个人助手');
    expect(launchProfileDisplayName(en, team), 'Default Team');
    expect(launchProfileDisplayName(zh, team), '默认团队');
  });

  test('user-created identities use persisted display', () {
    final en = AppLocalizationsEn();
    final personal = PersonalProfile(id: 'solo-1', display: 'My Solo');
    final team = TeamProfile(id: 'alpha', name: 'Alpha');

    expect(launchProfileDisplayName(en, personal), 'My Solo');
    expect(launchProfileDisplayName(en, team), 'Alpha');
  });
}
