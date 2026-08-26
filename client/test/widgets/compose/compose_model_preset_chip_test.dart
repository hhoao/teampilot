import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

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
}
