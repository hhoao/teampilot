import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/project_agent_prompt_presets.dart';

void main() {
  test('preset labels and bodies resolve for all ids', () {
    final l10n = AppLocalizationsEn();
    for (final preset in ProjectAgentPromptPreset.all) {
      expect(projectAgentPromptPresetLabel(l10n, preset.id), isNotEmpty);
      expect(projectAgentPromptPresetText(l10n, preset.id), isNotEmpty);
    }
  });
}
