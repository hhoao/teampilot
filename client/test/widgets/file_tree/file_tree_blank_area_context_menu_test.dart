import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/widgets/file_tree/file_tree_context_menu.dart';

class _FakeFilesystem implements Filesystem {
  _FakeFilesystem(Map<String, List<FsDirEntry>> dirs) : _dirs = dirs;

  final Map<String, List<FsDirEntry>> _dirs;
  final Set<String> _files = {};

  @override
  final p.Context pathContext = p.Context();

  @override
  Future<FsStat> stat(String path) async {
    if (_dirs.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    if (_files.contains(path)) {
      return const FsStat(kind: FsEntityKind.file, size: 0);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<void> ensureDir(String path) async {
    if (_dirs.containsKey(path)) return;
    _dirs[path] = [];
    final parent = pathContext.dirname(path);
    if (parent != path && _dirs.containsKey(parent)) {
      _dirs[parent] = [
        ..._dirs[parent]!,
        FsDirEntry(name: pathContext.basename(path), isDirectory: true),
      ];
    }
  }

  @override
  Future<void> writeString(String path, String content) async {
    _files.add(path);
  }

  @override
  Future<void> removeRecursive(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<String?> readString(String path) async => '';

  @override
  Future<List<int>?> readBytes(String path) async => [];

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async =>
      [];

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {}

  @override
  Future<void> atomicWrite(String path, String content) async {}

  @override
  Future<List<FsDirEntry>> listDir(String path) async =>
      _dirs[path] ?? const [];

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async => false;

  @override
  Future<String?> readSymlinkTarget(String linkPath) async => null;

  @override
  Future<String?> resolveSymlink(String path) async => null;

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {}

  @override
  Future<void> copyFile(String source, String destination) async {}

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async =>
      listDir(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async =>
      '/tmp';

  @override
  Future<void> appendString(String path, String content) async {}
}

Widget _host(FileTreeCubit cubit, {required bool desktopShellActions}) {
  return TpTheme(
    data: TpThemeData.fallback(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              unawaited(
                FileTreeContextMenu.showForBlankArea(
                  context: context,
                  tapDetails: details,
                  cubit: cubit,
                  targetRootDir: p.normalize('/proj'),
                  workspaceId: 'ws1',
                  desktopShellActions: desktopShellActions,
                ),
              );
            },
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    const Offset(200, 200),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _runOnDesktop(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<FileTreeCubit> _cubitWithRoot(WidgetTester tester) async {
  final cubit = FileTreeCubit(
    fs: _FakeFilesystem({
      p.normalize('/proj'): [const FsDirEntry(name: 'a.txt', isDirectory: false)],
    }),
  );
  await cubit.setRoot(p.normalize('/proj'));
  await tester.pump(const Duration(milliseconds: 20));
  return cubit;
}

void main() {
  testWidgets('blank-area menu shows trimmed items; Paste disabled', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot(tester);
      await tester.pumpWidget(_host(cubit, desktopShellActions: true));

      await _openMenu(tester);

      expect(find.text('New File'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Collapse all folders'), findsOneWidget);
      expect(find.text('Show hidden files'), findsOneWidget);
      expect(find.text('Open in Terminal'), findsOneWidget);
      // Row-menu-only items must be absent.
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Rename'), findsNothing);
      // No clipboard yet → Paste is disabled.
      final pasteItem = tester.widget<TpActionMenuItem>(
        find.widgetWithText(TpActionMenuItem, 'Paste'),
      );
      expect(pasteItem.enabled, isFalse);

      await cubit.close();
    });
  });

  testWidgets('Paste enabled after copyItem; terminal item hidden on ssh', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot(tester);
      cubit.copyItem(p.normalize('/proj/a.txt'));
      await tester.pumpWidget(_host(cubit, desktopShellActions: false));

      await _openMenu(tester);

      expect(find.text('Open in Terminal'), findsNothing);
      final pasteItem = tester.widget<TpActionMenuItem>(
        find.widgetWithText(TpActionMenuItem, 'Paste'),
      );
      expect(pasteItem.enabled, isTrue);

      await cubit.close();
    });
  });

  testWidgets('Show hidden files toggles cubit state', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot(tester);
      expect(cubit.state.showHiddenFiles, isFalse);
      await tester.pumpWidget(_host(cubit, desktopShellActions: true));

      await _openMenu(tester);
      await tester.tap(find.text('Show hidden files'));
      await tester.pump();

      expect(cubit.state.showHiddenFiles, isTrue);

      await cubit.close();
    });
  });

  testWidgets('New Folder creates inside the target root', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot(tester);
      await tester.pumpWidget(_host(cubit, desktopShellActions: true));

      await _openMenu(tester);
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();
      expect(find.text('New Folder'), findsOneWidget); // dialog title

      await tester.enterText(find.byType(TextField), 'sub');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        cubit.entriesFor(p.normalize('/proj')).map((e) => e.name),
        contains('sub'),
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await cubit.close();
    });
  });
}
