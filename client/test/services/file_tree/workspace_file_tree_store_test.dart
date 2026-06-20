import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  FileTreeCubit makeCubit() => FileTreeCubit(fs: LocalFilesystem());

  test('cubitFor returns the same instance per workspace id', () {
    final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);

    final a1 = store.cubitFor('ws-a');
    final a2 = store.cubitFor('ws-a');
    final b = store.cubitFor('ws-b');

    expect(identical(a1, a2), isTrue);
    expect(identical(a1, b), isFalse);

    store.dispose();
  });

  test('removeWorkspace closes and drops the cubit', () {
    final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);
    final a = store.cubitFor('ws-a');

    store.removeWorkspace('ws-a');

    expect(a.isClosed, isTrue);
    expect(identical(store.cubitFor('ws-a'), a), isFalse);

    store.dispose();
  });

  test('dispose closes every retained cubit', () {
    final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);
    final a = store.cubitFor('ws-a');
    final b = store.cubitFor('ws-b');

    store.dispose();

    expect(a.isClosed, isTrue);
    expect(b.isClosed, isTrue);
  });
}
