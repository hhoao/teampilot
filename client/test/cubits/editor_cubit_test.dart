import 'dart:io';

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
}
