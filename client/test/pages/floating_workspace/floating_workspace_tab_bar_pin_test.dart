import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_tab_bar.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

FloatingWorkspaceTabBar _bar({
  Set<String>? previewTabIds,
  Set<String>? pinnedTabIds,
  ValueChanged<String>? onPin,
  ValueChanged<String>? onUnpin,
  ValueChanged<String>? onSelect,
}) {
  return FloatingWorkspaceTabBar(
    tabs: const [
      FloatingTab(id: 'terminal:e1', surfaceId: 'terminal', title: 'Shell 1'),
    ],
    activeTabId: 'terminal:e1',
    onSelect: onSelect ?? (_) {},
    onClose: (_) {},
    onCloseOthers: (_) {},
    onCloseRight: (_) {},
    previewTabIds: previewTabIds ?? const {},
    pinnedTabIds: pinnedTabIds ?? const {},
    onPin: onPin,
    onUnpin: onUnpin,
  );
}

void main() {
  testWidgets('pinned tab shows pin icon instead of close', (tester) async {
    var unpinned = false;
    await tester.pumpWidget(
      _host(
        _bar(pinnedTabIds: {'terminal:e1'}, onUnpin: (_) => unpinned = true),
      ),
    );

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.byIcon(Icons.push_pin));
    await tester.pump();
    expect(unpinned, isTrue);
  });

  testWidgets('preview tab renders italic title', (tester) async {
    await tester.pumpWidget(_host(_bar(previewTabIds: {'terminal:e1'})));

    expect(find.byIcon(Icons.close), findsOneWidget);
    final text = tester.widget<Text>(find.text('Shell 1'));
    expect(text.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('single tap selects immediately (no double-tap window)', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(_host(_bar(onSelect: selected.add)));

    await tester.tap(find.text('Shell 1'));
    await tester.pump();
    // A chip with onDoubleTap would leave this empty until kDoubleTapTimeout.
    expect(selected, ['terminal:e1']);
  });

  testWidgets('normal tab is not italic and pin callback not called', (
    tester,
  ) async {
    var pinned = false;
    await tester.pumpWidget(_host(_bar(onPin: (_) => pinned = true)));

    final text = tester.widget<Text>(find.text('Shell 1'));
    expect(text.style?.fontStyle, isNot(FontStyle.italic));
    expect(pinned, isFalse);
  });
}
