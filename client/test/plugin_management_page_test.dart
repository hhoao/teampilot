import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/pages/plugin_management_page.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/runtime_storage_context.dart';

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
    home: Scaffold(
      body: BlocProvider.value(
        value: PluginCubit.test(state),
        child: child,
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
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('plugin-0'), findsOneWidget);
    expect(find.text('plugin-1'), findsOneWidget);
  });
}
