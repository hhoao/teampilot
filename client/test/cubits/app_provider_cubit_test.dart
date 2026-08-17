import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/credential_login_progress.dart';
import 'package:teampilot/services/provider/provider_import_service.dart';

class _SpyProviderImportService extends ProviderImportService {
  _SpyProviderImportService() : super(repository: AppProviderRepository());

  var importAllCalls = 0;
  final importForCliCalls = <CliTool>[];

  @override
  Future<List<ProviderImportResult>> importAllCatalogClis({
    required bool onlyIfEmpty,
  }) async {
    importAllCalls++;
    return [
      const ProviderImportResult(cli: CliTool.claude, added: 1),
      const ProviderImportResult(cli: CliTool.codex, added: 1),
    ];
  }

  @override
  Future<ProviderImportResult> importForCli(
    CliTool cli, {
    required bool onlyIfEmpty,
  }) async {
    importForCliCalls.add(cli);
    return ProviderImportResult(cli: cli, added: 1);
  }
}

void main() {
  late Directory temp;
  late AppProviderCubit cubit;
  late AppProviderRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('app_provider_cubit_');
    repository = AppProviderRepository(basePath: temp.path);
    cubit = AppProviderCubit(repository: repository, basePath: temp.path);
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('importAllFromExternal imports every catalog CLI', () async {
    final spy = _SpyProviderImportService();
    final allCliCubit = AppProviderCubit(
      repository: repository,
      importService: spy,
      basePath: temp.path,
    );
    addTearDown(allCliCubit.close);

    await repository.saveProviders(CliTool.claude, const [
      AppProviderConfig(id: 'claude-a', cli: CliTool.claude, name: 'Claude A'),
    ]);
    await repository.saveProviders(CliTool.codex, const [
      AppProviderConfig(id: 'codex-a', cli: CliTool.codex, name: 'Codex A'),
    ]);

    final results = await allCliCubit.importAllFromExternal();

    expect(spy.importAllCalls, 1);
    expect(spy.importForCliCalls, isEmpty);
    expect(results.map((r) => r.cli), containsAll([CliTool.claude, CliTool.codex]));
    expect(allCliCubit.state.providersFor(CliTool.claude).single.id, 'claude-a');
    expect(allCliCubit.state.providersFor(CliTool.codex).single.id, 'codex-a');
    expect(allCliCubit.state.statusMessage, contains('Imported'));
  });

  test('deleteProvider selects next provider within current cli', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(id: 'a', cli: CliTool.claude, name: 'A'),
    );
    await cubit.upsertProvider(
      const AppProviderConfig(id: 'b', cli: CliTool.claude, name: 'B'),
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
        cli: CliTool.claude,
        name: 'Claude Provider',
      ),
    );
    await cubit.setSelectedCli(CliTool.codex);
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'codex-provider',
        cli: CliTool.codex,
        name: 'Codex Provider',
      ),
    );

    await cubit.setSelectedCli(CliTool.claude);
    expect(cubit.state.selectedCli, CliTool.claude);
    expect(cubit.state.selectedId, 'claude-provider');

    await cubit.setSelectedCli(CliTool.codex);
    expect(cubit.state.selectedCli, CliTool.codex);
    expect(cubit.state.selectedId, 'codex-provider');
  });

  test('flashskyai models provider is normalized to provider id', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.flashskyai,
        name: 'DeepSeek',
        config: {
          'models': {
            'deepseek-chat': {
              'name': 'deepseek-chat',
              'provider': 'DeepSeek',
              'model': 'deepseek-chat',
              'enabled': true,
            },
          },
        },
      ),
    );

    final saved = (await repository.loadProviders(CliTool.flashskyai)).single;
    final models = saved.config['models'] as Map;
    final model = models['deepseek-chat'] as Map;
    expect(model['provider'], 'deepseek');
  });

  test('reportCredentialLoginProgress stores device code for the waiting UI', () {
    cubit.beginCredentialLogin('openai-official');
    cubit.reportCredentialLoginProgress(
      CredentialLoginProgress(
        deviceCode: 'WO3M-X8OIF',
        verificationUri: Uri.parse('https://auth.openai.com/codex/device'),
      ),
    );

    expect(cubit.state.credentialLoginProviderId, 'openai-official');
    expect(cubit.state.credentialLoginDeviceCode, 'WO3M-X8OIF');
    expect(
      cubit.state.credentialLoginVerificationUri,
      'https://auth.openai.com/codex/device',
    );

    cubit.clearCredentialLoginProgress();
    expect(cubit.state.credentialLoginDeviceCode, isNull);
    expect(cubit.state.credentialLoginProviderId, isNull);
  });
}
