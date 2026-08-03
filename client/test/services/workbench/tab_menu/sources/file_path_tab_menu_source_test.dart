import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workbench/tab_menu/sources/file_path_tab_menu_source.dart';
import 'package:teampilot/services/workbench/tab_menu/workbench_tab_menu_context.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  final source = FilePathTabMenuSource();

  WorkbenchTabMenuContext ctx({
    String? filePath,
    String? workspaceRoot,
    bool desktopShellActions = false,
    bool remoteFileManagerActions = false,
  }) {
    return WorkbenchTabMenuContext(
      l10n: l10n,
      kind: WorkbenchTabKind.file,
      tabId: 'tab-1',
      filePath: filePath,
      workspaceRoot: workspaceRoot,
      pinnable: false,
      pinned: false,
      desktopShellActions: desktopShellActions,
      remoteFileManagerActions: remoteFileManagerActions,
      onClose: () {},
    );
  }

  test('filePath null returns empty list', () {
    expect(source.buildItems(ctx()), isEmpty);
  });

  test('desktop shell actions includes full file menu in order', () {
    final items = source.buildItems(
      ctx(
        filePath: '/ws/src/a.dart',
        workspaceRoot: '/ws',
        desktopShellActions: true,
      ),
    );
    expect(items.map((item) => item.id), [
      'file.copy_path',
      'file.copy_relative_path',
      'file.reveal',
      'file.open_terminal',
      'file.open_external',
    ]);
    expect(
      items.singleWhere((item) => item.id == 'file.copy_path').label,
      l10n.fileTreeCopyPath,
    );
    expect(
      items.singleWhere((item) => item.id == 'file.copy_relative_path').label,
      l10n.fileTreeCopyRelativePath,
    );
    expect(
      items.singleWhere((item) => item.id == 'file.reveal').label,
      l10n.fileTreeOpenInFileManager,
    );
    expect(
      items.singleWhere((item) => item.id == 'file.open_terminal').label,
      l10n.fileTreeOpenInTerminal,
    );
    expect(
      items.singleWhere((item) => item.id == 'file.open_external').label,
      l10n.fileTreeOpenWithSystemApp,
    );
  });

  test('remote file manager actions includes copy paths and reveal only', () {
    final items = source.buildItems(
      ctx(
        filePath: '/ws/src/a.dart',
        workspaceRoot: '/ws',
        remoteFileManagerActions: true,
      ),
    );
    expect(items.map((item) => item.id), [
      'file.copy_path',
      'file.copy_relative_path',
      'file.reveal',
    ]);
  });

  test('no desktop or remote actions includes copy paths only', () {
    final items = source.buildItems(
      ctx(
        filePath: '/ws/src/a.dart',
        workspaceRoot: '/ws',
      ),
    );
    expect(items.map((item) => item.id), [
      'file.copy_path',
      'file.copy_relative_path',
    ]);
  });

  test('copy relative path is disabled when not relativizable', () {
    final items = source.buildItems(
      ctx(
        filePath: '/other/a.dart',
        workspaceRoot: '/ws',
        desktopShellActions: true,
      ),
    );
    final relative = items.singleWhere(
      (item) => item.id == 'file.copy_relative_path',
    );
    expect(relative.enabled, isFalse);
  });

  test('copy relative path is enabled when inside workspace root', () {
    final items = source.buildItems(
      ctx(
        filePath: '/ws/src/a.dart',
        workspaceRoot: '/ws',
        desktopShellActions: true,
      ),
    );
    final relative = items.singleWhere(
      (item) => item.id == 'file.copy_relative_path',
    );
    expect(relative.enabled, isTrue);
  });
}
