import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../support/in_memory_filesystem.dart';

void main() {
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
      staged: false,
      title: 'a.dart',
      diffText: 'diff --git a',
    );
    cubit.openDiff(
      workspaceId: ws,
      absolutePath: '/repo/a.dart',
      staged: true,
      title: 'a.dart',
      diffText: 'diff --git b',
    );

    final bucket = cubit.state.bucket(ws);
    expect(bucket.openDiffs.length, 2);
    expect(
      bucket.openDiffs[WorkbenchTabId.diffKey('/repo/a.dart', staged: false)]
          ?.diffText,
      'diff --git a',
    );

    final dir = await Directory.systemTemp.createTemp('teampilot_editor_diff_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.dart')..writeAsStringSync('x');
    await cubit.openFile(ws, file.path);

    cubit.closeDiff(
      ws,
      WorkbenchTabId.diffKey('/repo/a.dart', staged: false),
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
