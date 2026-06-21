import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('openFile loads text and marks dirty after edit', () async {
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_');
    final file = File('${dir.path}/sample.txt');
    await file.writeAsString('hello');

    final cubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(cubit.close);

    await cubit.openFile(file.path);
    expect(cubit.state.hasOpenFiles, isTrue);
    expect(cubit.state.activePath, file.path);
    expect(cubit.controllerFor(file.path)?.text, 'hello');

    cubit.controllerFor(file.path)!.text = 'hello world';
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isDirty(file.path), isTrue);

    final saved = await cubit.saveFile(file.path);
    expect(saved, isTrue);
    expect(cubit.state.isDirty(file.path), isFalse);
    expect(await file.readAsString(), 'hello world');

    cubit.controllerFor(file.path)!.text = 'changed again';
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isDirty(file.path), isTrue);

    cubit.revertActive();
    expect(cubit.state.isDirty(file.path), isFalse);
    expect(cubit.controllerFor(file.path)?.text, 'hello world');

    await dir.delete(recursive: true);
  });

  test('editorKeyFor is a stable, per-file GlobalKey', () async {
    // The editor uses this GlobalKey so a host-subtree swap (e.g. the chat
    // workbench switching WorkspaceEditorOverlay branches as a session
    // connects) MOVES the CodeEditor instead of remounting it — otherwise the
    // old + new editor briefly share the file's controller in one frame and
    // re_editor calls setState() during build.
    final dir = await Directory.systemTemp.createTemp('teampilot_editor_key_');
    addTearDown(() => dir.delete(recursive: true));
    final a = File('${dir.path}/a.txt')..writeAsStringSync('a');
    final b = File('${dir.path}/b.txt')..writeAsStringSync('b');

    final cubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(cubit.close);

    await cubit.openFile(a.path);
    await cubit.openFile(b.path);

    final keyA = cubit.editorKeyFor(a.path);
    final keyB = cubit.editorKeyFor(b.path);

    expect(keyA, isA<GlobalKey>());
    expect(keyB, isA<GlobalKey>());
    // Stable across calls (would re-mount the editor every rebuild otherwise).
    expect(identical(cubit.editorKeyFor(a.path), keyA), isTrue);
    // Distinct per file so switching the active file remounts the right editor.
    expect(identical(keyA, keyB), isFalse);

    // Closing the file releases its key; reopening allocates a fresh one.
    cubit.closeFile(cubit.state.openPaths.indexOf(a.path), force: true);
    expect(cubit.editorKeyFor(a.path), isNull);
    await cubit.openFile(a.path);
    expect(identical(cubit.editorKeyFor(a.path), keyA), isFalse);
  });
}
