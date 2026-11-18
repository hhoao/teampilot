import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/install/job_log_store.dart';
import 'package:teampilot/widgets/install/job_log_dialog.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_progress_cubit.dart';

const _key = InstallJobKey(
  kind: InstallJobKind.cliExecutable,
  target: 'claude',
);

Widget _host(InstallJobRegistry registry, Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: RepositoryProvider<InstallJobRegistry>.value(
        value: registry,
        child: Scaffold(body: child),
      ),
    ),
  );
}

InstallJobRegistry _registry(JobLogStore store) =>
    InstallJobRegistry(progressCubit: TestProgressCubit(), logs: store);

void main() {
  testWidgets('streams live lines and keeps the final content', (tester) async {
    final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
    final registry = _registry(store);
    addTearDown(registry.dispose);
    final token = store.tokenFor(_key);
    final writer = store.begin(key: _key, title: 'Install Claude');
    writer.line('npm install claude');

    await tester.pumpWidget(_host(registry, const SizedBox.shrink()));
    unawaited(
      showInstallJobLogDialog(
        tester.element(find.byType(Scaffold)),
        token: token,
        title: 'Install Claude',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('npm install claude'), findsOneWidget);

    writer.line('added 1 package');
    await tester.pump();
    expect(find.textContaining('added 1 package'), findsOneWidget);

    await writer.close();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('added 1 package'), findsOneWidget);
  });

  testWidgets('shows the unavailable state for a missing log', (tester) async {
    final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
    final registry = _registry(store);
    addTearDown(registry.dispose);

    await tester.pumpWidget(_host(registry, const SizedBox.shrink()));
    unawaited(
      showInstallJobLogDialog(
        tester.element(find.byType(Scaffold)),
        token: 'missing',
        title: 'Install Claude',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Log unavailable — the file was cleaned up.'),
      findsOneWidget,
    );
  });

  testWidgets('fits a short window without overflowing', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);

    final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
    final registry = _registry(store);
    addTearDown(registry.dispose);
    final token = store.tokenFor(_key);
    final writer = store.begin(key: _key, title: 'Install Claude');
    for (var i = 0; i < 12; i++) {
      writer.line('npm line $i');
    }
    await writer.close();

    await tester.pumpWidget(_host(registry, const SizedBox.shrink()));
    unawaited(
      showInstallJobLogDialog(
        tester.element(find.byType(Scaffold)),
        token: token,
        title: 'Install Claude',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('npm line 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
