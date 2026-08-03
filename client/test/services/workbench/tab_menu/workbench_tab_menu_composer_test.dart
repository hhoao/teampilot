import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workbench/tab_menu/workbench_tab_menu_composer.dart';
import 'package:teampilot/services/workbench/tab_menu/workbench_tab_menu_context.dart';
import 'package:teampilot/services/workbench/tab_menu/workbench_tab_menu_source.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('single non-empty group has no divider', () {
    final specs = WorkbenchTabMenuComposer.compose(
      [_FixedSource([_item('a.one')])],
      _fakeCtx(l10n),
    );
    expect(specs.where((s) => s.isDivider), isEmpty);
    expect(specs.single.value, 'a.one');
  });

  test('skips empty groups and inserts one divider between kept groups', () {
    final specs = WorkbenchTabMenuComposer.compose(
      [
        _FixedSource([_item('a.one'), _item('a.two')]),
        _FixedSource(const []),
        _FixedSource([_item('b.one')]),
      ],
      _fakeCtx(l10n),
    );
    expect(specs.map((s) => s.isDivider ? '|' : s.value).toList(), [
      'a.one',
      'a.two',
      '|',
      'b.one',
    ]);
  });

  test('all empty yields empty specs', () {
    expect(
      WorkbenchTabMenuComposer.compose([_FixedSource(const [])], _fakeCtx(l10n)),
      isEmpty,
    );
  });
}

WorkbenchTabMenuContext _fakeCtx(AppLocalizations l10n) {
  return WorkbenchTabMenuContext(
    l10n: l10n,
    kind: WorkbenchTabKind.file,
    tabId: 'tab-1',
    pinnable: false,
    pinned: false,
    desktopShellActions: false,
    remoteFileManagerActions: false,
    onClose: () {},
  );
}

WorkbenchTabMenuItem _item(String id) {
  return WorkbenchTabMenuItem(
    id: id,
    icon: Icons.abc,
    label: id,
    onAction: () {},
  );
}

class _FixedSource implements WorkbenchTabMenuSource {
  const _FixedSource(this.items);

  final List<WorkbenchTabMenuItem> items;

  @override
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx) => items;
}
