import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/mcp_probe_snapshot.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/pages/mcp/mcp_management_page.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';
import 'package:teampilot/services/mcp/mcp_server_probe_service.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../../services/mcp/support/fake_mcp_probe_handshake.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late Filesystem fs;
  late McpRepository repository;
  late McpCubit cubit;
  late DiscoverySettingsCubit discoverySettingsCubit;

  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  setUp(() {
    fs = InMemoryFilesystem();
    repository = McpRepository(
      catalog: McpCatalogService(
        catalogPath: '/root/mcp/mcp_servers.json',
        fs: fs,
      ),
      storage: testHomeStorage,
    );
    cubit = McpCubit(
      repository,
      storage: testHomeStorage,
      probeService: McpServerProbeService(
        handshake: FakeMcpProbeHandshake(
          resultBuilder: (server) {
            if (server.id != 'fetch') {
              return McpHandshakeResult.ok(const [
                McpProbeTool(name: 'health_check'),
              ]);
            }
            return McpHandshakeResult.ok(const [
              McpProbeTool(name: 'health_check'),
              McpProbeTool(name: 'open_files'),
            ]);
          },
        ),
        timeout: const Duration(seconds: 2),
      ),
    );
    discoverySettingsCubit = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
  });

  tearDown(() {
    cubit.close();
    discoverySettingsCubit.close();
  });

  Future<void> pumpListPage(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
            child: BlocProvider<McpCubit>.value(
              value: cubit,
              child: BlocProvider<DiscoverySettingsCubit>.value(
                value: discoverySettingsCubit,
                child: const Scaffold(
                  body: McpManagementPage(section: McpSection.installed),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const fetchServer = McpServer(
    id: 'fetch',
    name: 'Fetch',
    server: {'type': 'stdio', 'command': 'uvx'},
  );

  testWidgets('enabled fetch row shows online tool count after probe', (
    tester,
  ) async {
    await cubit.upsert(fetchServer);
    await pumpListPage(tester);

    expect(find.byKey(const Key('mcp-probe-status-fetch')), findsOneWidget);
    expect(find.text('2 tools'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('disabled fetch row hides probe status', (tester) async {
    await cubit.upsert(fetchServer.copyWith(enabled: false));
    await pumpListPage(tester);

    expect(find.text('Fetch'), findsOneWidget);
    expect(find.byKey(const Key('mcp-probe-status-fetch')), findsNothing);
  });

  testWidgets('tapping the name opens tools dialog, not the editor', (
    tester,
  ) async {
    await cubit.upsert(fetchServer);
    await pumpListPage(tester);

    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();

    expect(find.text('health_check'), findsOneWidget);
    expect(find.byKey(const Key('mcp-id')), findsNothing);
  });

  testWidgets('edit icon still opens the JSON editor', (tester) async {
    await cubit.upsert(fetchServer);
    await pumpListPage(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsOneWidget);
  });
}
