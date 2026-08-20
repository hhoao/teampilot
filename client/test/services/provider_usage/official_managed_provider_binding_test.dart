import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_usage/official_managed_provider_binding.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('maps official adapters to CLI provider rows', () {
    final codex = OfficialManagedProviderBinding.forAdapter(
      'official-codex-subscription',
    );
    expect(codex?.cli, CliTool.codex);
    expect(codex?.appProviderId, 'openai-official');
    expect(codex?.template.id, 'openai-official');

    final claude = OfficialManagedProviderBinding.forAdapter(
      'official-claude-subscription',
    );
    expect(claude?.cli, CliTool.claude);
    expect(claude?.appProviderId, 'claude-official');
    expect(claude?.template.id, 'claude-official');

    expect(OfficialManagedProviderBinding.forAdapter('http-json'), isNull);
  });

  test('creates the official CLI provider row when it is missing', () async {
    final fs = InMemoryFilesystem();
    final cubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    addTearDown(cubit.close);

    final binding = OfficialManagedProviderBinding.forAdapter(
      'official-claude-subscription',
    )!;
    expect(cubit.state.providersFor(CliTool.claude), isEmpty);

    final created = await ensureOfficialAppProvider(
      cubit: cubit,
      binding: binding,
    );

    expect(created.id, 'claude-official');
    expect(
      cubit.state.providersFor(CliTool.claude).single.id,
      'claude-official',
    );

    final again = await ensureOfficialAppProvider(
      cubit: cubit,
      binding: binding,
    );
    expect(again.id, 'claude-official');
    expect(cubit.state.providersFor(CliTool.claude), hasLength(1));
  });
}
