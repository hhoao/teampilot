import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/pages/mcp/mcp_editor_dialog.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late Filesystem fs;
  late McpRepository repository;
  late McpCubit cubit;

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
  });

  tearDown(() => cubit.close());

  Future<void> pumpHost(
    WidgetTester tester, {
    McpServer? existing,
  }) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: BlocProvider<McpCubit>.value(
            value: cubit,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMcpEditorDialog(
                    context,
                    cubit: cubit,
                    existing: existing,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('save creates the server and closes the dialog', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mcp-id')), 'fetch');
    await tester.enterText(find.byKey(const Key('mcp-name')), 'Fetch');
    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsNothing);
    final saved = await repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.id, 'fetch');
    expect(saved.single.name, 'Fetch');
    expect(saved.single.server['type'], 'stdio');
  });

  testWidgets('required fields block save', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsOneWidget);
    expect(find.text('MCP ID and display name are required.'), findsWidgets);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('invalid JSON keeps the dialog open', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mcp-id')), 'fetch');
    await tester.enterText(find.byKey(const Key('mcp-name')), 'Fetch');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('mcp-json')),
        matching: find.byType(TextField),
      ),
      '{oops',
    );
    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsOneWidget);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('cancel closes the dialog without saving', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mcp-id')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mcp-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsNothing);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('edit pre-fills fields and disables the id', (tester) async {
    final existing = McpServer(
      id: 'fetch',
      name: 'Fetch',
      server: const {
        'type': 'stdio',
        'command': 'uvx',
        'args': ['mcp-server-fetch'],
      },
      description: 'Fetch server',
      tags: const ['utility'],
    );
    await repository.upsert(existing);

    await pumpHost(tester, existing: existing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(const Key('mcp-id'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-name')))
          .controller!
          .text,
      'Fetch',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-desc')))
          .controller!
          .text,
      'Fetch server',
    );

    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsNothing);
    final saved = await repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.id, 'fetch');
    expect(saved.single.tags, ['utility']);
  });
}
