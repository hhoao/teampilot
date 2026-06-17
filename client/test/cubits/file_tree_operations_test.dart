import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/file_tree_cubit.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('copy and paste creates a duplicate file', () async {
    final fs = InMemoryFilesystem();
    const root = '/proj';
    const source = '/proj/a.txt';
    await fs.ensureDir(root);
    await fs.writeString(source, 'hello');

    final cubit = FileTreeCubit(fs: fs);
    await cubit.setRoot(root);
    cubit.copyItem(source);

    await cubit.pasteInto(root);

    expect(await fs.readString('/proj/a.txt'), 'hello');
    expect(cubit.state.clipboard, isNotNull);
    await cubit.close();
  });

  test('cut and paste moves a file and clears clipboard', () async {
    final fs = InMemoryFilesystem();
    const root = '/proj';
    const nested = '/proj/src';
    const source = '/proj/src/a.txt';
    await fs.ensureDir(nested);
    await fs.writeString(source, 'move-me');

    final cubit = FileTreeCubit(fs: fs);
    await cubit.setRoot(root);
    cubit.cutItem(source);

    await cubit.pasteInto(root);

    expect(await fs.readString('/proj/a.txt'), 'move-me');
    expect((await fs.stat(source)).exists, isFalse);
    expect(cubit.state.clipboard, isNull);
    await cubit.close();
  });

  test('renameItem changes the file name', () async {
    final fs = InMemoryFilesystem();
    const root = '/proj';
    const source = '/proj/old.txt';
    await fs.ensureDir(root);
    await fs.writeString(source, 'x');

    final cubit = FileTreeCubit(fs: fs);
    await cubit.setRoot(root);
    await cubit.renameItem(source, 'new.txt');

    expect(await fs.readString('/proj/new.txt'), 'x');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.close();
  });

  test('createFile and createFolder add entries', () async {
    final fs = InMemoryFilesystem();
    const root = '/proj';
    await fs.ensureDir(root);

    final cubit = FileTreeCubit(fs: fs);
    await cubit.setRoot(root);
    await cubit.createFolder(root, 'src');
    await cubit.createFile(p.join(root, 'src'), 'main.dart');

    expect((await fs.stat('/proj/src')).isDirectory, isTrue);
    expect(await fs.readString('/proj/src/main.dart'), '');
    await cubit.close();
  });
}
