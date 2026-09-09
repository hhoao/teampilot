import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workbench/tab_menu/sources/split_tab_menu_source.dart';
import 'package:teampilot/services/workbench/tab_menu/workbench_tab_menu_context.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  WorkbenchTabMenuContext ctx({
    void Function()? onSplitRight,
    void Function()? onSplitDown,
  }) {
    return WorkbenchTabMenuContext(
      l10n: l10n,
      kind: WorkbenchTabKind.session,
      tabId: 'sess-1',
      pinnable: true,
      pinned: false,
      desktopShellActions: false,
      remoteFileManagerActions: false,
      onClose: () {},
      onSplitRight: onSplitRight,
      onSplitDown: onSplitDown,
    );
  }

  test('produces split right + split down when both callbacks supplied', () {
    final items = SplitTabMenuSource().buildItems(
      ctx(onSplitRight: () {}, onSplitDown: () {}),
    );
    expect(items.map((i) => i.id), ['split.right', 'split.down']);
    expect(items[0].label, l10n.tabMenuSplitRight);
    expect(items[1].label, l10n.tabMenuSplitDown);
    expect(items.every((i) => i.enabled && !i.destructive), isTrue);
  });

  test('omits entries whose callback is missing', () {
    expect(SplitTabMenuSource().buildItems(ctx()), isEmpty);
    final rightOnly = SplitTabMenuSource().buildItems(ctx(onSplitRight: () {}));
    expect(rightOnly.map((i) => i.id), ['split.right']);
    final downOnly = SplitTabMenuSource().buildItems(ctx(onSplitDown: () {}));
    expect(downOnly.map((i) => i.id), ['split.down']);
  });

  test('actions invoke the supplied callbacks', () {
    var rightCalls = 0;
    var downCalls = 0;
    final items = SplitTabMenuSource().buildItems(
      ctx(onSplitRight: () => rightCalls++, onSplitDown: () => downCalls++),
    );
    items[0].onAction();
    items[1].onAction();
    expect(rightCalls, 1);
    expect(downCalls, 1);
  });
}
