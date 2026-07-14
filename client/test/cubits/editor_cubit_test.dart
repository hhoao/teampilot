import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/editor/editor_messages.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../services/editor_platform/fake_ts_worker.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ws = 'ws-test';

  test('openFile loads text and marks dirty after edit', () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_');
    final file = File('${dir.path}/sample.txt');
    await file.writeAsString('hello');

    final cubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(cubit.close);

    await cubit.openFile(ws, file.path);
    expect(cubit.state.bucket(ws).hasOpenFiles, isTrue);
    expect(cubit.state.bucket(ws).openFilePaths, [file.path]);
    expect(cubit.controllerFor(ws, file.path)?.text, 'hello');

    cubit.controllerFor(ws, file.path)!.text = 'hello world';
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.bucket(ws).isDirty(file.path), isTrue);

    final saved = await cubit.saveFile(ws, file.path);
    expect(saved, isTrue);
    expect(cubit.state.bucket(ws).isDirty(file.path), isFalse);
    expect(await file.readAsString(), 'hello world');

    cubit.controllerFor(ws, file.path)!.text = 'changed again';
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.bucket(ws).isDirty(file.path), isTrue);

    cubit.revertFile(ws, file.path);
    expect(cubit.state.bucket(ws).isDirty(file.path), isFalse);
    expect(cubit.controllerFor(ws, file.path)?.text, 'hello world');

    await dir.delete(recursive: true);
  });

  test('editorKeyFor is a stable, per-file GlobalKey', () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_key_');
    addTearDown(() => dir.delete(recursive: true));
    final a = File('${dir.path}/a.txt')..writeAsStringSync('a');
    final b = File('${dir.path}/b.txt')..writeAsStringSync('b');

    final cubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(cubit.close);

    await cubit.openFile(ws, a.path);
    await cubit.openFile(ws, b.path);

    final keyA = cubit.editorKeyFor(ws, a.path);
    final keyB = cubit.editorKeyFor(ws, b.path);

    expect(keyA, isA<GlobalKey>());
    expect(keyB, isA<GlobalKey>());
    expect(identical(cubit.editorKeyFor(ws, a.path), keyA), isTrue);
    expect(identical(keyA, keyB), isFalse);

    cubit.closeFile(ws, a.path, force: true);
    expect(cubit.editorKeyFor(ws, a.path), isNull);
    await cubit.openFile(ws, a.path);
    expect(identical(cubit.editorKeyFor(ws, a.path), keyA), isFalse);
  });

  test('openDiff keeps staged and unstaged separate; close leaves file', () async {
    final cubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(cubit.close);

    cubit.openDiff(
      workspaceId: ws,
      absolutePath: '/repo/a.dart',
      source: WorkbenchDiffSource.unstaged,
      title: 'a.dart',
      diffText: 'diff --git a',
    );
    cubit.openDiff(
      workspaceId: ws,
      absolutePath: '/repo/a.dart',
      source: WorkbenchDiffSource.staged,
      title: 'a.dart',
      diffText: 'diff --git b',
    );

    final bucket = cubit.state.bucket(ws);
    expect(bucket.openDiffs.length, 2);
    expect(
      bucket.openDiffs[WorkbenchTabId.diffKey(
            '/repo/a.dart',
            source: WorkbenchDiffSource.unstaged,
          )]
          ?.diffText,
      'diff --git a',
    );

    final dir = await Directory.systemTemp.createTemp('teampilot_editor_diff_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.dart')..writeAsStringSync('x');
    await cubit.openFile(ws, file.path);

    cubit.closeDiff(
      ws,
      WorkbenchTabId.diffKey(
        '/repo/a.dart',
        source: WorkbenchDiffSource.unstaged,
      ),
    );
    expect(cubit.state.bucket(ws).openDiffs.length, 1);
    expect(cubit.state.bucket(ws).openFilePaths, [file.path]);
  });

  test('file buckets are isolated per workspace', () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_ws_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.txt')..writeAsStringSync('hi');

    final cubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(cubit.close);

    await cubit.openFile('ws-a', file.path);
    expect(cubit.state.bucket('ws-a').openFilePaths, [file.path]);
    expect(cubit.state.bucket('ws-b').openFilePaths, isEmpty);
  });

  test('wires a DocumentSession + token provider for a highlightable file',
      () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_ts_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.json')
      ..writeAsStringSync('{"hello": "world"}');

    final pool = FakeTsWorkerPool();
    final cubit = EditorCubit(fs: LocalFilesystem(), workerPool: pool);
    addTearDown(cubit.close);

    await cubit.openFile(ws, file.path);

    // JSON resolves to the json pack, so a worker session is opened and the
    // viewport is colored before the file reports "open".
    expect(cubit.documentSessionFor(ws, file.path), isNotNull);
    expect(pool.handles, hasLength(1));
    final provider = cubit.tokenProviderFor(ws, file.path);
    expect(provider, isNotNull);
    expect(provider!.tokensForLine(0), isNotEmpty);
  });

  test('plain-text file opens with no worker session or token provider',
      () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_txt_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/notes.txt')..writeAsStringSync('hello');

    final pool = FakeTsWorkerPool();
    final cubit = EditorCubit(fs: LocalFilesystem(), workerPool: pool);
    addTearDown(cubit.close);

    await cubit.openFile(ws, file.path);

    // A session object exists but the file is plain text: no worker attach.
    expect(pool.handles, isEmpty);
    expect(cubit.tokenProviderFor(ws, file.path)!.tokensForLine(0), isEmpty);
  });

  test('editing forwards an incremental edit to the session', () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_edit_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.json')..writeAsStringSync('{"a": "b"}');

    final pool = FakeTsWorkerPool();
    final cubit = EditorCubit(fs: LocalFilesystem(), workerPool: pool);
    addTearDown(cubit.close);

    await cubit.openFile(ws, file.path);
    final queriesAfterOpen = pool.queryCount;

    // Insert before the closing quote of the value: {"a": "b"} -> {"a": "bX"}.
    cubit.controllerFor(ws, file.path)!.text = '{"a": "bX"}';
    await pumpEventQueue();

    // applyEdit enqueues a re-tokenization query for the edited/viewport lines.
    expect(pool.queryCount, greaterThan(queriesAfterOpen));
    expect(cubit.state.bucket(ws).isDirty(file.path), isTrue);
  });

  test('closeFile disposes the DocumentSession worker attachment', () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_close_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.json')..writeAsStringSync('{"a": "b"}');

    final pool = FakeTsWorkerPool();
    final cubit = EditorCubit(fs: LocalFilesystem(), workerPool: pool);
    addTearDown(cubit.close);

    await cubit.openFile(ws, file.path);
    final handle = pool.handles.single;
    expect(handle.isClosed, isFalse);

    cubit.closeFile(ws, file.path, force: true);

    expect(cubit.documentSessionFor(ws, file.path), isNull);
    expect(cubit.tokenProviderFor(ws, file.path), isNull);
    expect(handle.isClosed, isTrue);
    expect(handle.disposeSent, isTrue);
  });

  test('closeFile cancels in-flight open so late read does not reopen', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate);
    fs.files['/repo/a.txt'] = 'hello';

    final cubit = EditorCubit(fs: fs);
    addTearDown(cubit.close);

    final pending = cubit.openFile(ws, '/repo/a.txt');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.bucket(ws).loadingPaths, contains('/repo/a.txt'));

    expect(cubit.closeFile(ws, '/repo/a.txt', force: true), isTrue);
    expect(cubit.state.bucket(ws).loadingPaths, isEmpty);

    gate.complete();
    await pending;
    expect(cubit.state.bucket(ws).openFilePaths, isEmpty);
    expect(cubit.controllerFor(ws, '/repo/a.txt'), isNull);
  });

  test('openFile loads image bytes without text controller', () async {
    final fs = InMemoryFilesystem();
    fs.byteFiles['/repo/dot.png'] = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ];
    final cubit = EditorCubit(fs: fs);
    addTearDown(cubit.close);

    await cubit.openFile(ws, '/repo/dot.png');
    expect(cubit.state.bucket(ws).openFilePaths, ['/repo/dot.png']);
    expect(cubit.controllerFor(ws, '/repo/dot.png'), isNull);
    expect(cubit.bytesFor(ws, '/repo/dot.png'), isNotNull);
    expect(cubit.documentSessionFor(ws, '/repo/dot.png'), isNull);

    cubit.closeFile(ws, '/repo/dot.png', force: true);
    expect(cubit.bytesFor(ws, '/repo/dot.png'), isNull);
  });

  test('openFile rejects oversized images', () async {
    final fs = InMemoryFilesystem();
    fs.byteFiles['/repo/big.png'] = List<int>.filled(kEditorMaxImageBytes + 1, 0);
    final cubit = EditorCubit(fs: fs);
    addTearDown(cubit.close);

    await cubit.openFile(ws, '/repo/big.png');
    expect(cubit.state.bucket(ws).openFilePaths, isEmpty);
    expect(
      cubit.state.bucket(ws).errorByPath['/repo/big.png'],
      EditorMessage.imageTooLarge,
    );
  });
}

class _GatedFilesystem extends InMemoryFilesystem {
  _GatedFilesystem(this._gate);

  final Completer<void> _gate;

  @override
  Future<FsStat> stat(String path) async {
    await _gate.future;
    return super.stat(path);
  }
}
