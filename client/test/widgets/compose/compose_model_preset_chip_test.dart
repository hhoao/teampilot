import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import 'package:teampilot/widgets/compose/compose_menu_chip.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

final _palette = WorkspaceChatLandingPalette(ColorScheme.light());

void main() {
  group('simpleLaunchChipLabel', () {
    test('empty draft returns emptyLabel', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: null,
          provider: null,
          model: null,
          emptyLabel: 'Use preset',
        ),
        'Use preset',
      );
    });

    test('prefers preset name when set', () {
      expect(
        simpleLaunchChipLabel(
          presetName: 'Work',
          cli: CliTool.claude,
          provider: 'claude-official',
          model: 'opus',
          emptyLabel: 'Use preset',
        ),
        'Work',
      );
    });

    test('custom shows model only (CLI via leading icon)', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: CliTool.claude,
          provider: 'claude-official',
          model: 'opus',
          emptyLabel: 'Use preset',
        ),
        'opus',
      );
    });

    test('custom falls back to provider when model empty', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: CliTool.claude,
          provider: 'claude-official',
          model: null,
          emptyLabel: 'Use preset',
        ),
        'claude-official',
      );
    });

    test('custom with no model or provider returns emptyLabel', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: CliTool.claude,
          provider: null,
          model: null,
          emptyLabel: 'Use preset',
        ),
        'Use preset',
      );
    });
  });

  group('ComposeToolbarChip long label', () {
    testWidgets('caps label width and reveals full text via Tooltip', (
      tester,
    ) async {
      const label = 'deepseek-v4-pro[1m]-very-long-preset-name';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: ComposeToolbarChip(
                palette: _palette,
                icon: Icons.abc,
                label: label,
                labelMaxWidth: 120,
              ),
            ),
          ),
        ),
      );

      final chipSize = tester.getSize(find.byType(ComposeToolbarChip));
      expect(chipSize.width, lessThan(200));

      final tooltip = find.byType(Tooltip);
      expect(tooltip, findsOneWidget);
      expect(tester.widget<Tooltip>(tooltip).message, label);
    });

    testWidgets('short label shows no Tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComposeToolbarChip(
              palette: _palette,
              icon: Icons.abc,
              label: 'sonnet',
              labelMaxWidth: 120,
            ),
          ),
        ),
      );

      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
