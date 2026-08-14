import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/right_tools/file_tree_panel.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';
import '../../support/test_runtime_context.dart';

// Same enhanced fake as Task 1 (stat honors notFound; ensureDir/writeString
// mutate state so create flows are observable).
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
    _dirs[path] ??= [];
    final parent = pathContext.dirname(path);
    if (parent != path &&
        !_dirs[parent]!.any((e) => e.name == pathContext.basename(path))) {
      _dirs[parent]!.add(
        FsDirEntry(name: pathContext.basename(path), isDirectory: true),
      );
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

Widget _panel({
  required FileTreeCubit cubit,
  required RuntimeContext workContext,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: Scaffold(
        body: BlocProvider.value(
          value: WorkbenchCubit(),
          child: BlocProvider.value(
            value: FloatingWorkspaceCubit(),
            child: RightToolsLifecycle(
              data: RightToolsLifecycleData(
                scope: const WorkspaceToolsScopeState(resolving: true),
                fileTreeCubit: cubit,
                pokeOnTurnEnd: () {},
                ensureFileTreeReady: () {},
              ),
              child: SizedBox(
                width: 320,
                height: 420,
                child: FileTreePanel(
                  cubit: cubit,
                  workContext: workContext,
                  workspaceId: 'ws1',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _rightClickAt(WidgetTester tester, Offset point) async {
  final gesture = await tester.startGesture(
    point,
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

void main() {
  testWidgets('blank-area right-click shows blank menu (single root)', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          p.normalize('/proj'): [
            const FsDirEntry(name: 'a.txt', isDirectory: false),
          ],
        }),
      );
      await cubit.setRoot(p.normalize('/proj'));
      await tester.pumpWidget(_panel(cubit: cubit, workContext: testRuntimeContext('/home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Blank area: below the only row, near the panel bottom.
      final rect = tester.getRect(find.byKey(AppKeys.fileTreePanel));
      await _rightClickAt(tester, Offset(rect.center.dx, rect.bottom - 24));

      // Blank menu markers: Refresh present, row-only Cut absent.
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Collapse all folders'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);

      await cubit.close();
    });
  });

  testWidgets('right-click on (empty) opens the blank menu', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          p.normalize('/proj'): <FsDirEntry>[],
        }),
      );
      await cubit.setRoot(p.normalize('/proj'));
      await tester.pumpWidget(
        _panel(cubit: cubit, workContext: testRuntimeContext('/home')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _rightClickAt(tester, tester.getCenter(find.text('(empty)')));

      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);

      await cubit.close();
    });
  });

  testWidgets('row right-click keeps the row menu', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          p.normalize('/proj'): [
            const FsDirEntry(name: 'a.txt', isDirectory: false),
          ],
        }),
      );
      await cubit.setRoot(p.normalize('/proj'));
      await tester.pumpWidget(_panel(cubit: cubit, workContext: testRuntimeContext('/home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _rightClickAt(tester, tester.getCenter(find.text('a.txt')));

      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);

      await cubit.close();
    });
  });

  testWidgets('multi-root: blank right-click targets the pointer root band', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final a = p.normalize('/projA');
      final b = p.normalize('/projB');
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          a: [const FsDirEntry(name: 'x.dart', isDirectory: false)],
          b: [const FsDirEntry(name: 'y.dart', isDirectory: false)],
        }),
      );
      await cubit.setRoots([a, b]);
      await tester.pumpWidget(_panel(cubit: cubit, workContext: testRuntimeContext('/home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Blank below all rows resolves to the nearest band → root B.
      final rect = tester.getRect(find.byKey(AppKeys.fileTreePanel));
      await _rightClickAt(tester, Offset(rect.center.dx, rect.bottom - 24));

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'z');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        cubit.entriesFor(b).map((e) => e.name),
        contains('z'),
      );

      // Drain the success-toast timer before the test ends.
      await tester.pump(const Duration(seconds: 2));

      await cubit.close();
    });
  });
}
