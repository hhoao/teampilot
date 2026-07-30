import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';

ImportMode resolveFileTreeImportMode({
  required bool fromExternalOs,
  required bool sameFs,
  required bool copyModifier,
}) {
  if (fromExternalOs || !sameFs) return ImportMode.copy;
  return copyModifier ? ImportMode.copy : ImportMode.move;
}

bool fileTreePathsShareFilesystem({
  required Filesystem sourceFs,
  required Filesystem destFs,
  required RuntimeContext? sourceWorkContext,
  required RuntimeContext? destWorkContext,
}) {
  if (identical(sourceFs, destFs)) return true;
  final sourceCtx = sourceWorkContext;
  final destCtx = destWorkContext;
  if (sourceCtx != null && destCtx != null) {
    return sourceCtx.target.id == destCtx.target.id;
  }
  return false;
}

class FileTreeDropIngestor {
  FileTreeDropIngestor({
    required this.cubit,
    required this.importService,
    required this.hostLocalFs,
    required this.onConflict,
    required this.isCopyModifierPressed,
  });

  final FileTreeCubit cubit;
  final WorkspaceImportService importService;
  final Filesystem hostLocalFs;
  final ConflictResolver onConflict;
  final bool Function() isCopyModifierPressed;

  Future<ImportPlan> prepareAt({
    required String destDir,
    required WorkspaceDragPayload payload,
    required bool fromExternalOs,
  }) async {
    final sources = _sourcesFromPayload(payload);
    final destFs = cubit.fsFor(destDir);
    final sourceFs = _resolveSourceFs(
      sources: sources,
      destDir: destDir,
      fromExternalOs: fromExternalOs,
    );
    final sameFs = fromExternalOs
        ? false
        : fileTreePathsShareFilesystem(
            sourceFs: sourceFs,
            destFs: destFs,
            sourceWorkContext: cubit.workContextFor(sources.first.path),
            destWorkContext: cubit.workContextFor(destDir),
          );
    final mode = resolveFileTreeImportMode(
      fromExternalOs: fromExternalOs,
      sameFs: sameFs,
      copyModifier: isCopyModifierPressed(),
    );

    final planned = await importService.planSources(sourceFs, sources);

    return ImportPlan(
      sources: sources,
      destDir: destDir,
      mode: mode,
      sourceFs: sourceFs,
      destFs: destFs,
      flattenedFileCount: planned.files.length,
      maxFileBytes: planned.maxBytes,
      destIsLocal: _destIsLocal(destDir),
    );
  }

  Future<ImportSummary> runPrepared(
    ImportPlan plan, {
    required bool Function() isCancelled,
  }) async {
    final summary = await importService.run(
      plan,
      onConflict: onConflict,
      isCancelled: isCancelled,
    );
    await _refreshAfterImport(plan);
    return summary;
  }

  Future<ImportSummary> consumeAt({
    required String destDir,
    required WorkspaceDragPayload payload,
    required bool fromExternalOs,
    bool Function()? isCancelled,
  }) async {
    final plan = await prepareAt(
      destDir: destDir,
      payload: payload,
      fromExternalOs: fromExternalOs,
    );
    return runPrepared(plan, isCancelled: isCancelled ?? () => false);
  }

  Filesystem _resolveSourceFs({
    required List<ImportSource> sources,
    required String destDir,
    required bool fromExternalOs,
  }) {
    if (fromExternalOs) return hostLocalFs;
    return cubit.fsFor(sources.first.path);
  }

  bool _destIsLocal(String destDir) {
    final workContext = cubit.workContextFor(destDir);
    if (workContext == null) return true;
    return workContext.mode == StorageBackendMode.native;
  }

  List<ImportSource> _sourcesFromPayload(WorkspaceDragPayload payload) {
    return [
      for (final ref in payload.refs)
        ImportSource(path: ref.nativePath, isDirectory: ref.isDirectory),
    ];
  }

  Future<void> _refreshAfterImport(ImportPlan plan) async {
    final pathContext = plan.destFs.pathContext;
    final dirs = <String>{plan.destDir};
    if (plan.mode == ImportMode.move) {
      for (final source in plan.sources) {
        dirs.add(pathContext.dirname(source.path));
      }
    }
    await cubit.refreshPaths(dirs);
  }
}
