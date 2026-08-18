import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import 'package:teampilot/widgets/cli/cli_brand_icon.dart';
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
      expect(specs[0].iconWidget, isNotNull);
      expect(specs[1].selected, isTrue);
      expect(specs[1].iconWidget, isNotNull);
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
      expect(item.icon, Icons.terminal_outlined);
    });
  });

  group('ComposeModelPresetChip', () {
    testWidgets('trigger shows CliBrandIcon for selected preset CLI', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final palette = WorkspaceChatLandingPalette(
                  Theme.of(context).colorScheme,
                );
                return ComposeModelPresetChip(
                  palette: palette,
                  sameCliPresets: [
                    CliPreset(
                      id: 'a',
                      name: 'Alpha',
                      cli: CliTool.cursor,
                      provider: 'p',
                      model: 'm',
                      createdAt: 0,
                      updatedAt: 0,
                    ),
                  ],
                  selectedPresetId: 'a',
                  label: 'Alpha',
                  emptyHintLabel: 'No presets',
                  onPresetSelected: (_) {},
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(CliBrandIcon), findsOneWidget);
      final brand = tester.widget<CliBrandIcon>(find.byType(CliBrandIcon));
      expect(brand.cli, CliTool.cursor);
    });
  });

  group('ComposePermissionChip', () {
    testWidgets('shows default label and forwards bool selection', (
      tester,
    ) async {
      LaunchSecurityPolicy? selected;
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
                  launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
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

      expect(selected, LaunchSecurityPolicy.fullAccess);
    });

    testWidgets('preserves an intermediate normalized policy', (tester) async {
      LaunchSecurityPolicy? selected;
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
                  launchSecurityPolicy: LaunchSecurityPolicy.askReadOnlyTrusted,
                  defaultLabel: 'Default',
                  fullAccessLabel: 'Full access',
                  askReadOnlyLabel: 'Ask / read-only / trusted hooks',
                  autoApproveWorkspaceWriteLabel:
                      'Auto-approve / workspace write / trusted hooks',
                  customLabel: 'Custom policy',
                  onSelected: (value) => selected = value,
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Ask / read-only / trusted hooks'), findsOneWidget);
      await tester.tap(find.text('Ask / read-only / trusted hooks'));
      await tester.pumpAndSettle();
      expect(
        find.text('Auto-approve / workspace write / trusted hooks'),
        findsOneWidget,
      );
      await tester.tap(
        find.text('Auto-approve / workspace write / trusted hooks'),
      );
      await tester.pumpAndSettle();

      expect(selected, LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted);
    });
  });
}
