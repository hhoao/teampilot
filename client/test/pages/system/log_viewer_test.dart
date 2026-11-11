import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/system/log_viewer_content.dart';
import 'package:teampilot/pages/system/log_viewer_panel.dart';
import 'package:teampilot/pages/system/log_viewer_toolbar.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

import '../../support/post_frame_test_harness.dart';

Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

LogViewerToolbar _toolbar({
  required Future<void> Function() onCopyAll,
  required Future<void> Function() onCopyPath,
  bool acpFramesEnabled = false,
  ValueChanged<bool>? onAcpFramesChanged,
}) {
  return LogViewerToolbar(
    logFiles: const ['/logs/app.log'],
    selectedFile: '/logs/app.log',
    searchController: TextEditingController(),
    selectedLevel: 'ALL',
    compactView: true,
    wrapLines: true,
    reverseOrder: false,
    acpFramesEnabled: acpFramesEnabled,
    lineCount: 2,
    onFileSelected: (_) {},
    onSearchChanged: (_) {},
    onLevelChanged: (_) {},
    onCompactViewChanged: (_) {},
    onWrapLinesChanged: (_) {},
    onAcpFramesChanged: onAcpFramesChanged ?? (_) {},
    onRefresh: () async {},
    onCopyPath: onCopyPath,
    onCopyAll: onCopyAll,
    onClearOld: () async {},
    onReverseOrderChanged: (_) {},
  );
}

void main() {
  testWidgets('actions menu offers copy all and invokes callback', (
    tester,
  ) async {
    var copyAllCalls = 0;
    var copyPathCalls = 0;
    await tester.pumpWidget(
      _host(
        _toolbar(
          onCopyAll: () async => copyAllCalls++,
          onCopyPath: () async => copyPathCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menu = tester.widget<TpActionMenuButton>(
      find.byType(TpActionMenuButton),
    );
    final copyAll = menu.specs.where((s) => s.value == 'copyAll').single;
    expect(copyAll.label, 'Copy all logs');

    menu.onSelected(copyAll.value);
    await tester.pump();
    expect(copyAllCalls, 1);
    expect(copyPathCalls, 0);
  });

  testWidgets('copy log path action still routes to onCopyPath', (
    tester,
  ) async {
    var copyPathCalls = 0;
    await tester.pumpWidget(
      _host(
        _toolbar(
          onCopyAll: () async {},
          onCopyPath: () async {
            copyPathCalls++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menu = tester.widget<TpActionMenuButton>(
      find.byType(TpActionMenuButton),
    );
    final copyPath = menu.specs.where((s) => s.value == 'copy').single;

    menu.onSelected(copyPath.value);
    await tester.pump();

    expect(copyPathCalls, 1);
  });

  testWidgets('ACP frame toggle reflects state and reports changes', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      _host(
        _toolbar(
          onCopyAll: () async {},
          onCopyPath: () async {},
          acpFramesEnabled: false,
          onAcpFramesChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('ACP protocol frames (off by default)'));
    await tester.pump();

    expect(changes, [true]);
  });

  testWidgets('file log list is wrapped in a SelectionArea', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      _host(
        LogViewerBody(
          logFiles: const ['/logs/app.log'],
          loading: false,
          displayedLines: const ['INFO line one', 'ERROR line two'],
          wrapLines: true,
          scrollController: scrollController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('INFO line one'), findsOneWidget);
    expect(find.text('ERROR line two'), findsOneWidget);
  });

  testWidgets('search field uses the pill decoration', (tester) async {
    await tester.pumpWidget(
      _host(_toolbar(onCopyAll: () async {}, onCopyPath: () async {})),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });

  testWidgets('level dropdown lists files from that directory', (tester) async {
    setUpTestAppStorage();
    addTearDown(() async {
      await tester.runAsync(AppLogger.instance.resetForTest);
      tearDownTestAppStorage();
    });

    final root = AppPathsBootstrapper.current.basePath;
    await tester.runAsync(() async {
      await AppLogger.instance.initFileLogging(root);
      AppLogger.instance.i('info only line');
      AppLogger.instance.e('error only line', recordError: false);
      await AppLogger.instance.flushFileLogging();
      await File(p.join(root, 'logs', 'errors.jsonl')).writeAsString('{}\n');
    });

    await tester.pumpWidget(_host(const LogViewerPanel(useSurfaceCard: false)));
    await _pumpLogViewerIo(tester);

    final fileSelect = tester.widget<TpSelect<String>>(
      find.byKey(const Key('log-viewer-file')),
    );
    expect(
      fileSelect.items.every((path) => !path.endsWith('errors.jsonl')),
      isTrue,
    );
    expect(p.basename(fileSelect.initialItem ?? ''), 'latest.log');

    tester
        .widget<TpSelect<String>>(find.byKey(const Key('log-viewer-level')))
        .onChanged
        .call('ERROR');
    await _pumpLogViewerIo(tester);

    final errorSelect = tester.widget<TpSelect<String>>(
      find.byKey(const Key('log-viewer-file')),
    );
    expect(
      errorSelect.items.every(
        (path) => path.contains('${p.separator}error${p.separator}'),
      ),
      isTrue,
    );
    expect(p.basename(errorSelect.initialItem ?? ''), 'latest.log');

    tester
        .widget<TpSelect<String>>(find.byKey(const Key('log-viewer-level')))
        .onChanged
        .call('INFO');
    await _pumpLogViewerIo(tester);

    final infoSelect = tester.widget<TpSelect<String>>(
      find.byKey(const Key('log-viewer-file')),
    );
    expect(
      infoSelect.items.every(
        (path) => path.contains('${p.separator}info${p.separator}'),
      ),
      isTrue,
    );
  });
}

/// File listing/reading in [LogViewerPanel] is real dart:io; FakeAsync
/// [pumpAndSettle] cannot complete those futures (and a loading
/// [LinearProgressIndicator] would spin forever).
Future<void> _pumpLogViewerIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final fileReady = find
        .byKey(const Key('log-viewer-file'))
        .evaluate()
        .isNotEmpty;
    final loading = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    if (fileReady && !loading) return;
  }
  fail('Log viewer IO did not settle');
}
