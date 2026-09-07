import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_janitor.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late AppProviderCubit appCubit;

  setUp(() {
    fs = InMemoryFilesystem();
    appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
  });

  tearDown(() async {
    await appCubit.close();
  });

  test('clears credentialLink on rows referencing the deleted entry',
      () async {
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm1',
      ),
    );
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'other',
        cli: CliTool.claude,
        name: 'Other',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm2',
      ),
    );

    await ManagedProviderLinkJanitor(
      appProviderCubit: appCubit,
    ).clearLinksFor('m1');

    final rows = appCubit.state.providersFor(CliTool.claude);
    expect(rows.singleWhere((p) => p.id == 'deepseek').credentialLink, '');
    expect(rows.singleWhere((p) => p.id == 'other').credentialLink, 'm2');
  });

  test('no-op when nothing references the entry', () async {
    await ManagedProviderLinkJanitor(
      appProviderCubit: appCubit,
    ).clearLinksFor('nobody');
    expect(appCubit.state.providersFor(CliTool.claude), isEmpty);
  });
}
