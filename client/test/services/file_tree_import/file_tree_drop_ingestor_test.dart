import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/file_tree_root_mount.dart';
import 'package:teampilot/services/file_tree_import/file_tree_drop_ingestor.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/workspace_dnd/path_namespace.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';

import '../../support/in_memory_filesystem.dart';

Future<ConflictChoice> _overwriteConflict({
  required String destPath,
  required bool sourceIsDirectory,
  required bool destIsDirectory,
  required bool typeMismatch,
  required int remainingConflicts,
}) async =>
    ConflictChoice.overwrite;

void main() {
  group('resolveFileTreeImportMode', () {
    test('external OS drop always copies', () {
      expect(
        resolveFileTreeImportMode(
          fromExternalOs: true,
          sameFs: true,
          copyModifier: false,
        ),
        ImportMode.copy,
      );
      expect(
        resolveFileTreeImportMode(
          fromExternalOs: true,
          sameFs: false,
          copyModifier: true,
        ),
        ImportMode.copy,
      );
    });

    test('in-tree same-fs defaults to move unless copy modifier', () {
      expect(
        resolveFileTreeImportMode(
          fromExternalOs: false,
          sameFs: true,
          copyModifier: false,
        ),
        ImportMode.move,
      );
      expect(
        resolveFileTreeImportMode(
          fromExternalOs: false,
          sameFs: true,
          copyModifier: true,
        ),
        ImportMode.copy,
      );
    });

    test('in-tree cross-fs always copies', () {
      expect(
        resolveFileTreeImportMode(
          fromExternalOs: false,
          sameFs: false,
          copyModifier: false,
        ),
        ImportMode.copy,
      );
      expect(
        resolveFileTreeImportMode(
          fromExternalOs: false,
          sameFs: false,
          copyModifier: true,
        ),
        ImportMode.copy,
      );
    });
  });

  group('prepareAt', () {
    test('walks sources via planSources without writing', () async {
      final fs = InMemoryFilesystem();
      final root = p.normalize('/proj');
      final srcDir = p.join(root, 'src');
      final destDir = p.join(root, 'dest');
      await fs.ensureDir(srcDir);
      await fs.ensureDir(destDir);
      await fs.writeString(p.join(srcDir, 'a.txt'), 'aaa');
      await fs.writeString(p.join(srcDir, 'b.txt'), 'bbbb');

      final cubit = FileTreeCubit(fs: fs);
      await cubit.setRoot(root);

      final ingestor = FileTreeDropIngestor(
        cubit: cubit,
        importService: WorkspaceImportService(),
        hostLocalFs: fs,
        onConflict: _overwriteConflict,
        isCopyModifierPressed: () => false,
      );

      final payload = WorkspaceDragPayload(
        kind: DragPayloadKind.workspaceFile,
        refs: [
          WorkspaceFileRef(
            nativePath: srcDir,
            namespace: const PathNamespace.localPosix(),
            isDirectory: true,
          ),
        ],
      );

      final plan = await ingestor.prepareAt(
        destDir: destDir,
        payload: payload,
        fromExternalOs: false,
      );

      expect(plan.mode, ImportMode.move);
      expect(plan.flattenedFileCount, 2);
      expect(plan.maxFileBytes, 4);
      expect(plan.destDir, destDir);
      expect(identical(plan.sourceFs, plan.destFs), isTrue);
      expect(plan.destIsLocal, isTrue);

      // prepareAt must not copy yet.
      final destA = await fs.stat(p.join(destDir, 'a.txt'));
      expect(destA.exists, isFalse);

      await cubit.close();
    });
  });

  group('consumeAt', () {
    test('copies in-tree with modifier and refreshes dest', () async {
      final fs = InMemoryFilesystem();
      final root = p.normalize('/proj');
      final srcFile = p.join(root, 'src', 'file.txt');
      final destDir = p.join(root, 'dest');
      await fs.ensureDir(p.dirname(srcFile));
      await fs.ensureDir(destDir);
      await fs.writeString(srcFile, 'hello');

      final cubit = FileTreeCubit(fs: fs);
      await cubit.setRoot(root);
      cubit.toggleExpand(destDir);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ingestor = FileTreeDropIngestor(
        cubit: cubit,
        importService: WorkspaceImportService(),
        hostLocalFs: fs,
        onConflict: _overwriteConflict,
        isCopyModifierPressed: () => true,
      );

      final payload = WorkspaceDragPayload(
        kind: DragPayloadKind.workspaceFile,
        refs: [
          WorkspaceFileRef(
            nativePath: srcFile,
            namespace: const PathNamespace.localPosix(),
            isDirectory: false,
          ),
        ],
      );

      final summary = await ingestor.consumeAt(
        destDir: destDir,
        payload: payload,
        fromExternalOs: false,
      );

      expect(summary.succeeded, 1);
      expect(summary.failed, 0);

      final copied = p.join(destDir, 'file.txt');
      final copiedStat = await fs.stat(copied);
      expect(copiedStat.exists, isTrue);
      expect(await fs.readString(copied), 'hello');

      // Source remains after copy.
      expect((await fs.stat(srcFile)).exists, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        cubit.entriesFor(destDir).map((e) => e.name),
        contains('file.txt'),
      );

      await cubit.close();
    });

    test('external OS drop copies from hostLocalFs into workspace mount', () async {
      final hostFs = InMemoryFilesystem();
      final workspaceFs = InMemoryFilesystem();
      final hostFile = p.normalize('/host/drop.txt');
      final destDir = p.normalize('/ws/proj');
      await hostFs.writeString(hostFile, 'from-host');
      await workspaceFs.ensureDir(destDir);

      final cubit = FileTreeCubit();
      await cubit.mountRoots([
        FileTreeRootMount(path: destDir, filesystem: workspaceFs),
      ]);
      cubit.toggleExpand(destDir);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ingestor = FileTreeDropIngestor(
        cubit: cubit,
        importService: WorkspaceImportService(),
        hostLocalFs: hostFs,
        onConflict: _overwriteConflict,
        isCopyModifierPressed: () => false,
      );

      final payload = WorkspaceDragPayload(
        kind: DragPayloadKind.workspaceFile,
        refs: [
          WorkspaceFileRef(
            nativePath: hostFile,
            namespace: const PathNamespace.localPosix(),
            isDirectory: false,
          ),
        ],
      );

      final summary = await ingestor.consumeAt(
        destDir: destDir,
        payload: payload,
        fromExternalOs: true,
      );

      expect(summary.succeeded, 1);
      final destPath = p.join(destDir, 'drop.txt');
      expect((await workspaceFs.stat(destPath)).exists, isTrue);
      expect(
        await workspaceFs.readBytes(destPath),
        'from-host'.codeUnits,
      );

      await cubit.close();
    });
  });
}
