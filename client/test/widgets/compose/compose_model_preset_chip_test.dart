import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

void main() {
  final preset = CliPreset(
    id: 'a',
    name: 'Alpha',
    cli: CliTool.claude,
    provider: 'p',
    model: 'm',
    createdAt: 0,
    updatedAt: 0,
  );

  group('buildComposeModelPresetMenuSpecs', () {
    test('inserts custom action before manage when customLabel set', () {
      final specs = buildComposeModelPresetMenuSpecs(
        sameCliPresets: [preset],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        customLabel: 'Custom…',
        customSelected: true,
        managePresetsLabel: 'Add preset',
      );

      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.custom),
        isTrue,
      );
      expect(
        specs
            .where((s) => s.value == ComposeModelPresetChipAction.custom)
            .single
            .selected,
        isTrue,
      );

      final customIndex = specs.indexWhere(
        (s) => s.value == ComposeModelPresetChipAction.custom,
      );
      final manageIndex = specs.indexWhere(
        (s) => s.value == ComposeModelPresetChipAction.manage,
      );
      expect(customIndex, lessThan(manageIndex));
    });

    test('omits custom row when customLabel is null', () {
      final specs = buildComposeModelPresetMenuSpecs(
        sameCliPresets: [preset],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        managePresetsLabel: 'Add preset',
      );

      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.custom),
        isFalse,
      );
      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.manage),
        isTrue,
      );
    });
  });

  group('simpleLaunchChipLabel', () {
    test('empty draft returns emptyLabel', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: null,
          provider: null,
          model: null,
          emptyLabel: 'Use preset',
          cliLabel: (_) => 'Claude',
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
          cliLabel: (_) => 'Claude',
        ),
        'Work',
      );
    });

    test('cli and model summary', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: CliTool.claude,
          provider: 'claude-official',
          model: 'opus',
          emptyLabel: 'Use preset',
          cliLabel: (_) => 'Claude',
        ),
        'Claude · opus',
      );
    });

    test('cli and provider when model empty', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: CliTool.claude,
          provider: 'claude-official',
          model: null,
          emptyLabel: 'Use preset',
          cliLabel: (_) => 'Claude',
        ),
        'Claude · claude-official',
      );
    });

    test('cli only when model and provider empty', () {
      expect(
        simpleLaunchChipLabel(
          presetName: null,
          cli: CliTool.claude,
          provider: null,
          model: null,
          emptyLabel: 'Use preset',
          cliLabel: (_) => 'Claude',
        ),
        'Claude',
      );
    });
  });
}
