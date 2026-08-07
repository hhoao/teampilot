import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workbench/tab_menu/sources/builtin_close_tab_menu_source.dart';
import 'package:teampilot/services/workbench/tab_menu/workbench_tab_menu_context.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  final source = BuiltinCloseTabMenuSource();

  WorkbenchTabMenuContext ctx({
    bool pinnable = false,
    bool pinned = false,
    VoidCallback? onPin,
    VoidCallback? onCloseOthers,
    VoidCallback? onCloseRight,
    VoidCallback? onCloseAll,
  }) {
    return WorkbenchTabMenuContext(
      l10n: l10n,
      kind: WorkbenchTabKind.session,
      tabId: 'tab-1',
      pinnable: pinnable,
      pinned: pinned,
      desktopShellActions: false,
      remoteFileManagerActions: false,
      onClose: () {},
      onPin: onPin,
      onCloseOthers: onCloseOthers,
      onCloseRight: onCloseRight,
      onCloseAll: onCloseAll,
    );
  }

  test('pinnable + onPin includes builtin.pin with pin label when unpinned', () {
    final items = source.buildItems(ctx(pinnable: true, onPin: () {}));
    final pin = items.singleWhere((item) => item.id == 'builtin.pin');
    expect(pin.label, l10n.pinConversation);
  });

  test('pinnable + onPin includes builtin.pin with unpin label when pinned', () {
    final items = source.buildItems(
      ctx(pinnable: true, pinned: true, onPin: () {}),
    );
    final pin = items.singleWhere((item) => item.id == 'builtin.pin');
    expect(pin.label, l10n.unpinConversation);
  });

  test('not pinnable omits builtin.pin even when onPin is set', () {
    final items = source.buildItems(ctx(onPin: () {}));
    expect(items.any((item) => item.id == 'builtin.pin'), isFalse);
  });

  test('always includes builtin.close', () {
    final items = source.buildItems(ctx());
    expect(items.any((item) => item.id == 'builtin.close'), isTrue);
    expect(
      items.singleWhere((item) => item.id == 'builtin.close').label,
      l10n.closeTab,
    );
  });

  test('omits close_others and close_right when callbacks are null', () {
    final items = source.buildItems(ctx());
    expect(items.any((item) => item.id == 'builtin.close_others'), isFalse);
    expect(items.any((item) => item.id == 'builtin.close_right'), isFalse);
  });

  test('includes close_others and close_right when callbacks are present', () {
    final items = source.buildItems(
      ctx(onCloseOthers: () {}, onCloseRight: () {}),
    );
    expect(items.map((item) => item.id), [
      'builtin.close',
      'builtin.close_others',
      'builtin.close_right',
    ]);
    expect(
      items.singleWhere((item) => item.id == 'builtin.close_others').label,
      l10n.closeOtherTabs,
    );
    expect(
      items.singleWhere((item) => item.id == 'builtin.close_right').label,
      l10n.closeRightTabs,
    );
  });

  test('omits close_all when onCloseAll is null', () {
    final items = source.buildItems(ctx());
    expect(items.any((item) => item.id == 'builtin.close_all'), isFalse);
  });

  test('includes close_all after close_right when onCloseAll is present', () {
    final items = source.buildItems(
      ctx(onCloseOthers: () {}, onCloseRight: () {}, onCloseAll: () {}),
    );
    expect(items.map((item) => item.id), [
      'builtin.close',
      'builtin.close_others',
      'builtin.close_right',
      'builtin.close_all',
    ]);
    expect(
      items.singleWhere((item) => item.id == 'builtin.close_all').label,
      l10n.closeAllTabs,
    );
  });
}
