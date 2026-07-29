import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

void main() {
  group('buildComposeModelPresetMenuSpecs', () {
    test('includes custom action before manage when customLabel set', () {
      final specs = buildComposeModelPresetMenuSpecs(
        sameCliPresets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        customLabel: 'Custom…',
        customSelected: true,
        managePresetsLabel: 'Manage',
      );

      final values = specs.map((s) => s.value).toList();
      expect(values, contains(ComposeModelPresetChipAction.custom));
      expect(values, contains(ComposeModelPresetChipAction.manage));
      expect(
        values.indexOf(ComposeModelPresetChipAction.custom),
        lessThan(values.indexOf(ComposeModelPresetChipAction.manage)),
      );
      expect(
        specs
            .where((s) => s.value == ComposeModelPresetChipAction.custom)
            .single
            .selected,
        isTrue,
      );
    });

    test('omits custom row when customLabel is null', () {
      final specs = buildComposeModelPresetMenuSpecs(
        sameCliPresets: [
          CliPreset(
            id: 'p1',
            name: 'Alpha',
            cli: CliTool.claude,
            provider: 'anthropic',
            model: 'sonnet',
            effort: 'high',
            createdAt: 0,
            updatedAt: 0,
          ),
        ],
        selectedPresetId: 'p1',
        emptyHintLabel: 'No presets',
        managePresetsLabel: 'Manage',
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
}
