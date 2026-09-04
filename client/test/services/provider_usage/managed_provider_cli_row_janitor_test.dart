import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_cli_row_janitor.dart';

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

  AppProviderConfig _row(String id) => AppProviderConfig(
    id: id,
    cli: CliTool.cursor,
    name: 'Row $id',
  );

  ManagedProvider _entry(String id, String source) => ManagedProvider(
    id: id,
    name: 'Entry $id',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(
      url: 'https://cursor.com/api/usage-summary',
      credentialSource: source,
    ),
  );

  test('removeDedicatedRow deletes the catalog row and disk directory',
      () async {
    await appCubit.upsertProvider(_row('cursor-mp-managed-1'));
    await fs.ensureDir('/tp/providers/cursor/cursor-mp-managed-1/home/.config/cursor');
    await fs.writeString(
      '/tp/providers/cursor/cursor-mp-managed-1/home/.config/cursor/auth.json',
      '{"accessToken":"tok"}',
    );

    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).removeDedicatedRow(cli: CliTool.cursor, rowId: 'cursor-mp-managed-1');

    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-1'),
      isFalse,
    );
    expect((await fs.stat('/tp/providers/cursor/cursor-mp-managed-1')).exists,
        isFalse);
  });

  test('removeDedicatedRow tolerates a missing row and directory',
      () async {
    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).removeDedicatedRow(cli: CliTool.codex, rowId: 'codex-mp-none');
    // No throw; nothing to assert beyond reaching here.
  }, skip: false);

  test('sweep reclaims orphan -mp- rows and shared rows, keeps live ones',
      () async {
    await appCubit.upsertProvider(_row('cursor-mp-managed-live'));
    await appCubit.upsertProvider(_row('cursor-mp-managed-orphan'));
    await appCubit.upsertProvider(_row('cursor-account'));
    await appCubit.upsertProvider(_row('cursor-other'));
    await fs.ensureDir('/tp/providers/cursor/cursor-mp-managed-orphan/home');
    await fs.ensureDir('/tp/providers/cursor/cursor-account/home');

    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).sweep(entries: [_entry('managed-live', 'cli:cursor-mp-managed-live')]);

    final remaining =
        appCubit.state.providersFor(CliTool.cursor).map((r) => r.id).toSet();
    expect(remaining, {'cursor-mp-managed-live', 'cursor-other'});
    expect(
      (await fs.stat('/tp/providers/cursor/cursor-mp-managed-orphan')).exists,
      isFalse,
    );
    expect(
      (await fs.stat('/tp/providers/cursor/cursor-account')).exists,
      isFalse,
    );
  });

  test('sweep is a no-op on empty catalogs', () async {
    await ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    ).sweep(entries: const []);
    expect(appCubit.state.providersFor(CliTool.cursor), isEmpty);
  });
}
