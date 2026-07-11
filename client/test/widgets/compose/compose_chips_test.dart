import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';
import 'package:teampilot/widgets/compose/compose_permission_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildComposeModelPresetMenuSpecs', () {
    test('marks selected preset and includes manage row', () {
      final presets = [
        CliPreset(
          id: 'a',
          name: 'Alpha',
          cli: CliTool.claude,
          provider: 'p',
          model: 'm',
          createdAt: 0,
          updatedAt: 0,
        ),
        CliPreset(
          id: 'b',
          name: 'Beta',
          cli: CliTool.claude,
          provider: 'p',
          model: 'm',
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      final specs = buildComposeModelPresetMenuSpecs(
        sameCliPresets: presets,
        selectedPresetId: 'b',
        emptyHintLabel: 'No presets',
        managePresetsLabel: 'Manage',
      );

      expect(specs, hasLength(4));
      expect(specs[0].isDivider, isFalse);
      expect(specs[0].selected, isFalse);
      expect(specs[1].selected, isTrue);
      expect(specs[2].isDivider, isTrue);
      expect(specs[3].value, ComposeModelPresetChipAction.manage);
    });

    test('empty list shows disabled hint', () {
      final specs = buildComposeModelPresetMenuSpecs(
        sameCliPresets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
      );

      expect(specs, hasLength(1));
      final item = specs.single;
      expect(item.enabled, isFalse);
      expect(item.label, 'No presets');
    });
  });

  group('ComposePermissionChip', () {
    testWidgets('shows default label and forwards bool selection', (
      tester,
    ) async {
      bool? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final palette = WorkspaceChatLandingPalette(
                  Theme.of(context).colorScheme,
                );
                return ComposePermissionChip(
                  palette: palette,
                  dangerouslySkipPermissions: false,
                  defaultLabel: 'Default',
                  fullAccessLabel: 'Full access',
                  onSelected: (value) => selected = value,
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Default'), findsOneWidget);

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Full access'));
      await tester.pumpAndSettle();

      expect(selected, isTrue);
    });
  });
}
