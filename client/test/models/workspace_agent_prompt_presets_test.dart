import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/workspace_agent_prompt_presets.dart';

void main() {
  test('preset labels and bodies resolve for all ids', () {
    final l10n = AppLocalizationsEn();
    for (final preset in WorkspaceAgentPromptPreset.all) {
      expect(workspaceAgentPromptPresetLabel(l10n, preset.id), isNotEmpty);
      expect(workspaceAgentPromptPresetText(l10n, preset.id), isNotEmpty);
    }
  });
}
