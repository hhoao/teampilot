import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';

void main() {
  late Directory temp;
  late AppProviderCubit cubit;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('app_provider_cubit_');
    cubit = AppProviderCubit(
      repository: AppProviderRepository(basePath: temp.path),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('deleteProvider selects next provider within current cli', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'a',
        cli: AppProviderCli.claude,
        name: 'A',
      ),
    );
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'b',
        cli: AppProviderCli.claude,
        name: 'B',
      ),
    );
    cubit.selectProvider('a');

    await cubit.deleteProvider('a');

    expect(cubit.state.selectedId, 'b');
    expect(cubit.state.providers.map((p) => p.id), ['b']);
  });

  test('switching cli restores selected provider for that cli', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'claude-provider',
        cli: AppProviderCli.claude,
        name: 'Claude Provider',
      ),
    );
    await cubit.setSelectedCli(AppProviderCli.codex);
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'codex-provider',
        cli: AppProviderCli.codex,
        name: 'Codex Provider',
      ),
    );

    await cubit.setSelectedCli(AppProviderCli.claude);
    expect(cubit.state.selectedCli, AppProviderCli.claude);
    expect(cubit.state.selectedId, 'claude-provider');

    await cubit.setSelectedCli(AppProviderCli.codex);
    expect(cubit.state.selectedCli, AppProviderCli.codex);
    expect(cubit.state.selectedId, 'codex-provider');
  });
}
