import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/team_member_prompt_presets.dart';

void main() {
  test('preset labels and bodies resolve for all ids', () {
    final l10n = AppLocalizationsEn();
    for (final preset in TeamMemberPromptPreset.all) {
      expect(teamMemberPromptPresetLabel(l10n, preset.id), isNotEmpty);
      expect(teamMemberPromptPresetText(l10n, preset.id), isNotEmpty);
    }
  });
}
