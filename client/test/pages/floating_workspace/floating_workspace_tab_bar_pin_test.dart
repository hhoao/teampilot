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
  void Function(String tabId)? onDoubleTap,
}) {
  return FloatingWorkspaceTabBar(
    tabs: const [
      FloatingTab(id: 'terminal:e1', surfaceId: 'terminal', title: 'Shell 1'),
    ],
    activeTabId: 'terminal:e1',
    onSelect: (_) {},
    onClose: (_) {},
    onCloseOthers: (_) {},
    onCloseRight: (_) {},
    previewTabIds: previewTabIds ?? const {},
    pinnedTabIds: pinnedTabIds ?? const {},
    onPin: onPin,
    onUnpin: onUnpin,
    onDoubleTap: onDoubleTap,
  );
}

void main() {
  testWidgets('pinned tab shows pin icon instead of close', (tester) async {
    var unpinned = false;
    await tester.pumpWidget(_host(_bar(
      pinnedTabIds: {'terminal:e1'},
      onUnpin: (_) => unpinned = true,
    )));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.byIcon(Icons.push_pin));
    await tester.pump();
    expect(unpinned, isTrue);
  });

  testWidgets('preview tab renders italic title and double-tap fires',
      (tester) async {
    final doubleTapped = <String>[];
    await tester.pumpWidget(_host(_bar(
      previewTabIds: {'terminal:e1'},
      onDoubleTap: doubleTapped.add,
    )));

    expect(find.byIcon(Icons.close), findsOneWidget);
    final text = tester.widget<Text>(find.text('Shell 1'));
    expect(text.style?.fontStyle, FontStyle.italic);

    await tester.tap(find.text('Shell 1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Shell 1'));
    await tester.pump();
    expect(doubleTapped, ['terminal:e1']);
    // Flush the Tooltip wait timer so no pending timer trips the binding.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('normal tab is not italic and pin callback not called',
      (tester) async {
    var pinned = false;
    await tester.pumpWidget(_host(_bar(onPin: (_) => pinned = true)));

    final text = tester.widget<Text>(find.text('Shell 1'));
    expect(text.style?.fontStyle, isNot(FontStyle.italic));
    expect(pinned, isFalse);
  });
}
