import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/system/log_viewer_content.dart';
import 'package:teampilot/pages/system/log_viewer_toolbar.dart';

Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

LogViewerToolbar _toolbar({
  required Future<void> Function() onCopyAll,
  required Future<void> Function() onCopyPath,
}) {
  return LogViewerToolbar(
    logFiles: const ['/logs/app.log'],
    selectedFile: '/logs/app.log',
    searchController: TextEditingController(),
    selectedLevel: 'ALL',
    compactView: true,
    wrapLines: true,
    reverseOrder: false,
    lineCount: 2,
    onFileSelected: (_) {},
    onSearchChanged: (_) {},
    onLevelChanged: (_) {},
    onCompactViewChanged: (_) {},
    onWrapLinesChanged: (_) {},
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
      _host(_toolbar(onCopyAll: () async {}, onCopyPath: () async {
        copyPathCalls++;
      })),
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
}
