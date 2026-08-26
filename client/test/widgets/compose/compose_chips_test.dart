import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/session_chat_compose_section.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';
import 'package:teampilot/widgets/compose/compose_permission_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildComposeModelCascadeMenuSpecs', () {
    CliPreset preset(String id, String name) => CliPreset(
          id: id,
          name: name,
          cli: CliTool.claude,
          provider: 'p',
          model: 'm',
          createdAt: 0,
          updatedAt: 0,
        );

    List<TpActionMenuSpec> buildSpecs({
      required List<CliPreset> presets,
      String? selectedPresetId,
    }) {
      return buildComposeModelCascadeMenuSpecs(
        presets: presets,
        selectedPresetId: selectedPresetId,
        emptyHintLabel: 'No presets',
        emptyProvidersLabel: 'No providers configured',
        presetsLabel: 'Presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom model ID…',
        noModelsLabel: 'No model catalog',
        savePresetLabel: 'Save as preset',
        managePresetsLabel: 'Manage',
        cliGroups: const [],
        groupByCli: false,
      );
    }

    test('marks selected preset and orders savePreset before manage', () {
      final specs = buildSpecs(
        presets: [preset('a', 'Alpha'), preset('b', 'Beta')],
        selectedPresetId: 'b',
      );

      expect(specs.first.isSubmenu, isTrue);
      expect(specs.first.label, 'Presets');
      final presetRows = specs.first.children!.single.scrollChildren!;
      expect(presetRows.first.isDivider, isFalse);
      expect(presetRows[0].label, 'Alpha');
      expect(presetRows[0].selected, isFalse);
      expect(presetRows[0].iconWidget, isNotNull);
      expect(presetRows[1].selected, isTrue);
      expect(presetRows[1].iconWidget, isNotNull);

      final values = specs.map((s) => s.value).toList();
      expect(values, contains(ComposeModelPresetChipAction.savePreset));
      expect(values, contains(ComposeModelPresetChipAction.manage));
      expect(
        values.indexOf(ComposeModelPresetChipAction.savePreset),
        lessThan(values.indexOf(ComposeModelPresetChipAction.manage)),
      );
    });

    test('empty list shows disabled hint and keeps bottom actions', () {
      final specs = buildSpecs(presets: const [], selectedPresetId: null);

      expect(specs.first.enabled, isFalse);
      expect(specs.first.label, 'No presets');
      expect(specs.first.icon, Icons.terminal_outlined);

      final values = specs.map((s) => s.value).toList();
      expect(values, contains(ComposeModelPresetChipAction.savePreset));
      expect(values, contains(ComposeModelPresetChipAction.manage));
      expect(
        values.indexOf(ComposeModelPresetChipAction.savePreset),
        lessThan(values.indexOf(ComposeModelPresetChipAction.manage)),
      );
    });
  });

  group('teamPresetMenuSpecs', () {
    testWidgets('flat preset rows only: no submenu, no savePreset/manage', (
      tester,
    ) async {
      List<TpActionMenuSpec> specs = const [];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              specs = SessionChatComposeSection.teamPresetMenuSpecs(
                context: context,
                presets: [
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
                ],
                selectedPresetId: 'b',
                emptyHintLabel: 'No presets',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(specs.map((s) => s.value), ['a', 'b']);
      expect(specs[1].selected, isTrue);
      expect(specs[0].iconWidget, isNotNull);
      for (final spec in specs) {
        expect(spec.isDivider, isFalse);
        expect(spec.isSubmenu, isFalse);
        expect(spec.value, isNot(ComposeModelPresetChipAction.savePreset));
        expect(spec.value, isNot(ComposeModelPresetChipAction.manage));
      }
    });

    testWidgets('empty presets render only the disabled hint row', (
      tester,
    ) async {
      List<TpActionMenuSpec> specs = const [];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              specs = SessionChatComposeSection.teamPresetMenuSpecs(
                context: context,
                presets: const [],
                selectedPresetId: null,
                emptyHintLabel: 'No presets',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(specs, hasLength(1));
      expect(specs.single.enabled, isFalse);
      expect(specs.single.label, 'No presets');
      expect(specs.single.isSubmenu, isFalse);
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
