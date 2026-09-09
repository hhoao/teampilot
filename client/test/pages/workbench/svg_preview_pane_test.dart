import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/pages/workbench/svg_preview_pane.dart';
import 'package:teampilot/services/editor/editor_messages.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

const svgV1 =
    '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20">'
    '<rect width="108" height="20" fill="#555"/></svg>';
const svgV2 =
    '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50">'
    '<rect width="50" height="50" fill="#007ec6"/></svg>';

/// Delegating wrapper counting [Filesystem.readBytes] calls (delegation style:
/// test/services/agent_runtime/runtime_event_journal_test.dart).
class _CountingFilesystem implements Filesystem {
  _CountingFilesystem(this._inner);

  final Filesystem _inner;
  int readBytesCalls = 0;

  @override
  get pathContext => _inner.pathContext;

  @override
  Future<List<int>?> readBytes(String path) {
    readBytesCalls++;
    return _inner.readBytes(path);
  }

  @override
  Future<String?> readString(String path) => _inner.readString(path);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      _inner.readBytesRange(path, offset, length);

  @override
  Future<void> ensureDir(String path) => _inner.ensureDir(path);

  @override
  Future<void> appendString(String path, String content) =>
      _inner.appendString(path, content);

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      _inner.appendBytes(path, bytes);

  @override
  Future<FsStat> stat(String path) => _inner.stat(path);

  @override
  Future<void> writeString(String path, String content) =>
      _inner.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _inner.writeBytes(path, bytes);

  @override
  Future<void> atomicWrite(String path, String content) =>
      _inner.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => _inner.listDir(path);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      _inner.listDirRecursive(path);

  @override
  Future<void> removeRecursive(String path) => _inner.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => _inner.rename(from, to);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => _inner.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      _inner.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => _inner.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => _inner.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      _inner.copyFile(source, destination);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      _inner.createTempDir(prefix: prefix, parent: parent);
}

/// Holds [readBytes] for one path behind a [Completer] gate, so a slow read
/// for the old path can resolve after the new path's read (style:
/// test/services/workbench/workbench_editor_opener_test.dart _GatedFilesystem).
class _GatedReadFilesystem extends InMemoryFilesystem {
  _GatedReadFilesystem(this._gatedPath, this._gate);

  final String _gatedPath;
  final Completer<void> _gate;

  @override
  Future<List<int>?> readBytes(String path) async {
    if (path == _gatedPath) await _gate.future;
    return super.readBytes(path);
  }
}

Future<void> pumpPane(
  WidgetTester tester, {
  required EditorCubit editor,
  required String path,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<EditorCubit>.value(
          value: editor,
          child: SvgPreviewPane(workspaceId: 'ws', path: path),
        ),
      ),
    ),
  );
  // Bounded pumps instead of pumpAndSettle: PhotoView keeps scheduling
  // frames after the contained-scale-to-1:1 clamp, which never settles.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('renders svg bytes through PhotoView with zoom toolbar', (
    tester,
  ) async {
    final fs = InMemoryFilesystem()..files['/repo/icon.svg'] = svgV1;
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    await tester.runAsync(() => editor.openFile('ws', '/repo/icon.svg'));

    await pumpPane(tester, editor: editor, path: '/repo/icon.svg');

    expect(find.byType(PhotoView), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('invalid svg reports decode failure', (tester) async {
    final fs = InMemoryFilesystem()..files['/repo/bad.svg'] = 'not an svg';
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    await tester.runAsync(() => editor.openFile('ws', '/repo/bad.svg'));

    await pumpPane(tester, editor: editor, path: '/repo/bad.svg');
    // Extra frame for the post-frame reportImageDecodeFailed callback.
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      editor.state.bucket('ws').errorByPath['/repo/bad.svg'],
      EditorMessage.imageDecodeFailed,
    );
  });

  testWidgets('re-reads bytes after a save (dirty -> clean)', (tester) async {
    final inner = InMemoryFilesystem()..files['/repo/icon.svg'] = svgV1;
    final fs = _CountingFilesystem(inner);
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    await tester.runAsync(() => editor.openFile('ws', '/repo/icon.svg'));

    await pumpPane(tester, editor: editor, path: '/repo/icon.svg');
    expect(fs.readBytesCalls, 1);

    // Simulate an external edit + save: pane must re-read on dirty->clean.
    inner.files['/repo/icon.svg'] = svgV2;
    final controller = editor.controllerFor('ws', '/repo/icon.svg');
    expect(controller, isNotNull);
    controller!.text = svgV2;
    expect(editor.state.bucket('ws').isDirty('/repo/icon.svg'), isTrue);

    await tester.runAsync(() => editor.saveFile('ws', '/repo/icon.svg'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(fs.readBytesCalls, 2);
  });

  testWidgets('missing file shows read error', (tester) async {
    final fs = InMemoryFilesystem();
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    // No openFile: the pane reads directly from fs.

    await pumpPane(tester, editor: editor, path: '/repo/missing.svg');

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.editorPanelErrorMessage(EditorMessage.couldNotRead)),
      findsOneWidget,
    );
    expect(find.byType(PhotoView), findsNothing);
  });

  testWidgets('retarget to a new path ignores the stale pending load', (
    tester,
  ) async {
    final gate = Completer<void>();
    final fs = _GatedReadFilesystem('/repo/a.svg', gate)
      ..files['/repo/a.svg'] = svgV1
      ..files['/repo/b.svg'] = svgV2;
    final editor = EditorCubit(fs: fs);
    addTearDown(editor.close);
    // No openFile: the pane reads directly from fs.

    // Pump on path A; its read is parked on the gate.
    await pumpPane(tester, editor: editor, path: '/repo/a.svg');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Retarget the SAME pane state to path B; B's read resolves immediately.
    await pumpPane(tester, editor: editor, path: '/repo/b.svg');

    List<int> paneBytes() {
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      return (picture.bytesLoader as SvgBytesLoader).bytes;
    }

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(paneBytes(), utf8.encode(svgV2));

    // Now A's slow read resolves; the stale load must not overwrite B.
    gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(paneBytes(), utf8.encode(svgV2));
  });
}
