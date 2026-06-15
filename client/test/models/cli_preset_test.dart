import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  group('CliPreset', () {
    test('fromJson and toJson round-trip', () {
      final now = 1718400000000;
      final preset = CliPreset(
        id: 'abc-123',
        name: 'Claude Work',
        cli: CliTool.claude,
        provider: 'prov-1',
        model: 'claude-sonnet-4-6',
        effort: 'high',
        createdAt: now,
        updatedAt: now,
      );

      final json = preset.toJson();
      final restored = CliPreset.fromJson(json);

      expect(restored.id, 'abc-123');
      expect(restored.name, 'Claude Work');
      expect(restored.cli, CliTool.claude);
      expect(restored.provider, 'prov-1');
      expect(restored.model, 'claude-sonnet-4-6');
      expect(restored.effort, 'high');
      expect(restored.createdAt, now);
      expect(restored.updatedAt, now);
    });

    test('fromJson with missing optional fields uses defaults', () {
      final preset = CliPreset.fromJson({
        'id': 'x',
        'name': 'Minimal',
        'cli': 'claude',
        'provider': 'p',
        'model': 'm',
      });
      expect(preset.effort, '');
      expect(preset.createdAt, 0);
      expect(preset.updatedAt, 0);
    });

    test('copyWith updates individual fields', () {
      final preset = CliPreset(
        id: '1',
        name: 'Original',
        cli: CliTool.claude,
        provider: 'p1',
        model: 'm1',
        effort: '',
        createdAt: 1000,
        updatedAt: 1000,
      );
      final updated = preset.copyWith(name: 'Updated', effort: 'high');
      expect(updated.name, 'Updated');
      expect(updated.effort, 'high');
      expect(updated.id, '1'); // unchanged
      expect(updated.cli, CliTool.claude); // unchanged
    });

    test('equality and hashCode', () {
      final a = CliPreset(
        id: '1', name: 'A', cli: CliTool.claude,
        provider: 'p', model: 'm', effort: '',
        createdAt: 1, updatedAt: 1,
      );
      final b = CliPreset(
        id: '1', name: 'A', cli: CliTool.claude,
        provider: 'p', model: 'm', effort: '',
        createdAt: 1, updatedAt: 1,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
