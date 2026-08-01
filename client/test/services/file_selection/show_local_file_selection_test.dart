import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/services/file_selection/show_local_file_selection.dart';

class _FakeFilesystemPort implements TpFilesystemPort {
  @override
  List<TpFilesystemRoot> defaultRoots() => const [];

  @override
  String defaultBrowsePath() => '/';

  @override
  Future<List<TpFsEntry>> listDir(String path) async => const [];

  @override
  Future<List<TpFsEntry>>? Function(String rootPath, String query)?
      get searchFiles => null;

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<TpFsEntryKind> kindOf(String path) async => TpFsEntryKind.other;
}

class _FakePermissionPort implements TpPermissionPort {
  @override
  Future<bool> ensureStorageAccess() async => true;

  @override
  Future<bool> ensureGalleryAccess() async => false;

  @override
  Future<void> openAppSettings() async {}
}

class _FakeDesktopPickerPort implements TpDesktopPickerPort {
  _FakeDesktopPickerPort({this.directoryResult, this.filesResult});

  final List<TpPickedEntry>? directoryResult;
  final List<TpPickedEntry>? filesResult;
  int pickDirectoryCallCount = 0;
  int pickFilesCallCount = 0;

  @override
  Future<List<TpPickedEntry>?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    pickDirectoryCallCount++;
    return directoryResult;
  }

  @override
  Future<List<TpPickedEntry>?> pickFiles({
    bool allowMultiple = false,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
    int? maxSelectionCount,
  }) async {
    pickFilesCallCount++;
    return filesResult;
  }
}

TpFileSelectionDeps _testDeps({
  required bool Function() isDesktop,
  TpDesktopPickerPort? desktop,
}) {
  return TpFileSelectionDeps(
    filesystem: _FakeFilesystemPort(),
    permission: _FakePermissionPort(),
    desktop: desktop,
    strings: TpFileSelectionStrings.english(),
    isDesktop: isDesktop,
  );
}

void main() {
  testWidgets('showLocalFileSelection maps desktop directory pick to paths',
      (tester) async {
    final desktop = _FakeDesktopPickerPort(
      directoryResult: [
        const TpPickedEntry(path: '/workspace', kind: TpPickedKind.directory),
      ],
    );
    final deps = _testDeps(isDesktop: () => true, desktop: desktop);
    List<String>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showLocalFileSelection(
                  context,
                  deps: deps,
                  options: const TpFileSelectionOptions(
                    selectionMode: TpSelectionMode.directories,
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(desktop.pickDirectoryCallCount, 1);
    expect(result, ['/workspace']);
  });

  testWidgets('showLocalFileSelection returns null when picker cancelled',
      (tester) async {
    final desktop = _FakeDesktopPickerPort(directoryResult: null);
    final deps = _testDeps(isDesktop: () => true, desktop: desktop);
    List<String>? result = const [];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showLocalFileSelection(
                  context,
                  deps: deps,
                  options: const TpFileSelectionOptions(
                    selectionMode: TpSelectionMode.directories,
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
