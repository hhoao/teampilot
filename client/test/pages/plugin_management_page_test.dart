import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/pages/plugins/plugin_management_page.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-page-');
    final paths = AppPaths(tmp.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  Widget wrap(PluginState state, Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) => LayoutCubit(),
      child: Scaffold(
        body: BlocProvider.value(
          value: PluginCubit.test(state),
          child: child,
        ),
      ),
    ),
  );

  testWidgets('Installed section renders empty state', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(wrap(
      const PluginState(
        installed: [],
        marketplaces: [],
        status: PluginLoadStatus.ready,
      ),
      const PluginManagementPage(section: PluginSection.installed),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No plugins installed'), findsOneWidget);
  });

  testWidgets('Installed row shows per-CLI support disclosure', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    await tester.pumpWidget(wrap(
      PluginState(
        installed: [
          Plugin(
            id: 'p-hooks',
            name: 'hooks-only',
            description: 'test plugin',
            version: '1.0.0',
            directory: '/tmp/p',
            capabilities: const PluginCapabilities(
              hooks: [PluginHook(event: 'Stop', matcher: '.*')],
            ),
            installedAt: now,
            updatedAt: now,
          ),
        ],
        marketplaces: const [],
        status: PluginLoadStatus.ready,
      ),
      const PluginManagementPage(section: PluginSection.installed),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fully supported'), findsWidgets);
    expect(find.textContaining('Not applicable'), findsWidgets);
  });

  testWidgets('Marketplaces section lists default marketplace', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(wrap(
      const PluginState(
        installed: [],
        marketplaces: [
          PluginMarketplace(
            owner: 'anthropics',
            name: 'claude-plugins-official',
          ),
        ],
        status: PluginLoadStatus.ready,
      ),
      const PluginManagementPage(section: PluginSection.marketplaces),
    ));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('anthropics/claude-plugins-official'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('Discovery section uses lazy list for plugins', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    const plugins = [
      DiscoverablePlugin(
        key: 'anthropics:claude-plugins-official:p0',
        name: 'plugin-0',
        description: 'd0',
        version: '1',
        source: '.',
        marketplaceOwner: 'anthropics',
        marketplaceName: 'claude-plugins-official',
        marketplaceBranch: 'main',
      ),
      DiscoverablePlugin(
        key: 'anthropics:claude-plugins-official:p1',
        name: 'plugin-1',
        description: 'd1',
        version: '1',
        source: '.',
        marketplaceOwner: 'anthropics',
        marketplaceName: 'claude-plugins-official',
        marketplaceBranch: 'main',
      ),
    ];
    await tester.pumpWidget(wrap(
      const PluginState(
        installed: [],
        marketplaces: [
          PluginMarketplace(
            owner: 'anthropics',
            name: 'claude-plugins-official',
          ),
        ],
        discoverable: plugins,
        status: PluginLoadStatus.ready,
      ),
      const PluginManagementPage(section: PluginSection.discovery),
    ));
    await tester.pumpAndSettle();
    // Desktop layout also has a sidebar ListView; discovery uses bottom padding.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListView &&
            widget.padding == const EdgeInsets.only(bottom: 8),
      ),
      findsOneWidget,
    );
    expect(find.text('plugin-0'), findsOneWidget);
    expect(find.text('plugin-1'), findsOneWidget);
  });
}
