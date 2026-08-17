import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/pages/mcp/mcp_management_page.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';

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
    );
    cubit = McpCubit(repository);
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
      MaterialApp(
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
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Add MCP opens the editor dialog and cancel exits', (
    tester,
  ) async {
    await pumpListPage(tester);

    await tester.tap(find.text('Add MCP'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mcp-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsNothing);
  });

  testWidgets('edit row opens the dialog pre-filled', (tester) async {
    await cubit.upsert(
      const McpServer(
        id: 'fetch',
        name: 'Fetch',
        server: {'type': 'stdio', 'command': 'uvx'},
      ),
    );
    await pumpListPage(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-name')))
          .controller!
          .text,
      'Fetch',
    );
  });
}
