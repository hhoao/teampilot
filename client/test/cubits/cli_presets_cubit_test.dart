import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CliPresetsRepository repo;
  late CliPresetsCubit cubit;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = CliPresetsRepository(fs: fs, presetsPath: '/cli-presets.json');
    cubit = CliPresetsCubit(repository: repo);
  });

  test('initial state is empty idle', () {
    expect(cubit.state.presets, isEmpty);
    expect(cubit.state.status, CliPresetsLoadStatus.idle);
  });

  test('load populates presets', () async {
    await cubit.load();
    expect(cubit.state.status, CliPresetsLoadStatus.ready);
    expect(cubit.state.presets, isEmpty);
  });

  test('addPreset creates and persists a preset', () async {
    await cubit.load();

    await cubit.addPreset(
      name: 'New Preset',
      cli: CliTool.claude,
      provider: 'p1',
      model: 'm1',
      effort: 'high',
    );

    expect(cubit.state.presets.length, 1);
    final preset = cubit.state.presets.first;
    expect(preset.name, 'New Preset');
    expect(preset.cli, CliTool.claude);
    expect(preset.provider, 'p1');
    expect(preset.model, 'm1');
    expect(preset.effort, 'high');
    expect(preset.id, isNotEmpty);

    // Verify persistence
    final cubit2 = CliPresetsCubit(repository: repo);
    await cubit2.load();
    expect(cubit2.state.presets.length, 1);
    expect(cubit2.state.presets.first.id, preset.id);
  });

  test('updatePreset modifies an existing preset', () async {
    await cubit.load();
    await cubit.addPreset(
      name: 'Old', cli: CliTool.claude, provider: 'p', model: 'm',
    );
    final id = cubit.state.presets.first.id;

    await cubit.updatePreset(
      id: id,
      name: 'Updated',
      cli: CliTool.flashskyai,
      provider: 'p2',
      model: 'm2',
      effort: 'low',
    );

    final updated = cubit.state.presets.first;
    expect(updated.name, 'Updated');
    expect(updated.cli, CliTool.flashskyai);
    expect(updated.provider, 'p2');
    expect(updated.model, 'm2');
    expect(updated.effort, 'low');
  });

  test('deletePreset removes a preset', () async {
    await cubit.load();
    await cubit.addPreset(
      name: 'To Delete', cli: CliTool.claude, provider: 'p', model: 'm',
    );
    final id = cubit.state.presets.first.id;

    await cubit.deletePreset(id);

    expect(cubit.state.presets, isEmpty);
  });

  test('addPreset does not allow empty name', () async {
    await cubit.load();
    await cubit.addPreset(
      name: '  ', cli: CliTool.claude, provider: 'p', model: 'm',
    );
    // Should not add — name must be non-blank
    expect(cubit.state.presets, isEmpty);
  });
}
