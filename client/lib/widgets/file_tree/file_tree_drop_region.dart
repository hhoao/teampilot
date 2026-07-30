import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/services/file_tree/file_tree_visible_rows.dart';
import 'package:teampilot/services/file_tree_import/file_tree_drop_hit_test.dart';
import 'package:teampilot/services/file_tree_import/file_tree_drop_ingestor.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/import_progress_gate.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/workspace_dnd/workspace_drop_target.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';
import 'package:teampilot/widgets/file_tree/file_tree_import_dialogs.dart';
import 'package:teampilot/widgets/workspace_dnd/external_file_drop_region.dart';

/// Copy-modifier for in-tree drops: ⌥ on macOS, Ctrl elsewhere.
bool fileTreeCopyModifierPressed({
  TargetPlatform? platform,
  Set<LogicalKeyboardKey>? keys,
}) {
  final pressed = keys ?? HardwareKeyboard.instance.logicalKeysPressed;
  final plat = platform ?? defaultTargetPlatform;
  if (plat == TargetPlatform.macOS) {
    return pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
  }
  return pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight);
}

double fileTreeDropContentY({
  required double listLocalY,
  required double scrollOffset,
}) =>
    listLocalY + scrollOffset;

FileTreeDropRowKind fileTreeDropRowKind(FileTreeVisibleRow row) {
  if (row.isEmptyPlaceholder) return FileTreeDropRowKind.empty;
  if (row.isRoot) return FileTreeDropRowKind.rootChrome;
  if (row.entry.isDirectory) return FileTreeDropRowKind.folder;
  return FileTreeDropRowKind.file;
}

/// Root vertical bands derived from visible multi-root header rows.
List<({String rootPath, double top, double bottom})> buildFileTreeRootBands({
  required List<FileTreeVisibleRow> visibleRows,
  required List<String> rootPaths,
  double rowExtent = kFileTreeRowExtent,
}) {
  final rootIndices = <int>[];
  for (var i = 0; i < visibleRows.length; i++) {
    if (visibleRows[i].isRoot) rootIndices.add(i);
  }
  if (rootIndices.isEmpty) {
    if (rootPaths.isEmpty) return const [];
    return [
      (
        rootPath: rootPaths.first,
        top: 0,
        bottom: visibleRows.length * rowExtent,
      ),
    ];
  }

  final bands = <({String rootPath, double top, double bottom})>[];
  for (var r = 0; r < rootIndices.length; r++) {
    final start = rootIndices[r];
    final endExclusive = r + 1 < rootIndices.length
        ? rootIndices[r + 1]
        : visibleRows.length;
    bands.add((
      rootPath: visibleRows[start].path,
      top: start * rowExtent,
      bottom: endExclusive * rowExtent,
    ));
  }
  return bands;
}

/// Resolves panel drop dest from list content Y (localY + scrollOffset).
FileTreeDropHit resolveFileTreePanelDropHit({
  required double contentY,
  required List<FileTreeVisibleRow> visibleRows,
  required List<String> rootPaths,
  required p.Context Function(String path) pathContextFor,
  List<String> sourcePaths = const [],
  double rowExtent = kFileTreeRowExtent,
}) {
  if (visibleRows.isEmpty) {
    if (rootPaths.isEmpty) {
      return const FileTreeDropHit(destDir: null);
    }
    if (rootPaths.length == 1) {
      final root = rootPaths.first;
      return FileTreeDropHit(destDir: pathContextFor(root).normalize(root));
    }
    final bands = [
      for (var i = 0; i < rootPaths.length; i++)
        (
          rootPath: rootPaths[i],
          top: i * rowExtent,
          bottom: (i + 1) * rowExtent,
        ),
    ];
    final dest = resolveNearestRootDest(localY: contentY, rootBands: bands);
    return FileTreeDropHit(destDir: pathContextFor(dest).normalize(dest));
  }

  final index = contentY < 0 ? -1 : (contentY / rowExtent).floor();
  if (index >= 0 && index < visibleRows.length) {
    final row = visibleRows[index];
    return resolveFileTreeDropDest(
      kind: fileTreeDropRowKind(row),
      rowPath: row.path,
      pathContext: pathContextFor(row.path),
      sourcePaths: sourcePaths,
    );
  }

  final bands = buildFileTreeRootBands(
    visibleRows: visibleRows,
    rootPaths: rootPaths,
    rowExtent: rowExtent,
  );
  if (bands.isEmpty) {
    return const FileTreeDropHit(destDir: null);
  }
  final dest = resolveNearestRootDest(localY: contentY, rootBands: bands);
  return FileTreeDropHit(destDir: pathContextFor(dest).normalize(dest));
}

/// Stub [WorkspaceDropTarget] for file-tree OS drops (custom handler owns ingest).
class NoopWorkspaceDropTarget implements WorkspaceDropTarget {
  const NoopWorkspaceDropTarget();

  @override
  bool accepts(DragPayloadKind kind) => kind == DragPayloadKind.workspaceFile;

  @override
  Future<DropOutcome> consume(WorkspaceDragPayload payload) async =>
      DropOutcome.empty;
}

/// Inherited chrome for row DragTargets + OS hover highlight.
class FileTreeDropScope extends InheritedWidget {
  const FileTreeDropScope({
    required this.host,
    required super.child,
    super.key,
  });

  final FileTreeDropHost host;

  static FileTreeDropHost? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FileTreeDropScope>()?.host;
  }

  @override
  bool updateShouldNotify(FileTreeDropScope oldWidget) {
    return host.osHoverRowPath != oldWidget.host.osHoverRowPath ||
        host.osHoverAffordance != oldWidget.host.osHoverAffordance ||
        host.revision != oldWidget.host.revision;
  }
}

class FileTreeDropHost {
  FileTreeDropHost({
    required this.ingest,
    required this.cubit,
    this.osHoverRowPath,
    this.osHoverAffordance,
    this.revision = 0,
  });

  final Future<void> Function({
    required String destDir,
    required WorkspaceDragPayload payload,
    required bool fromExternalOs,
  })
  ingest;
  final FileTreeCubit cubit;
  final String? osHoverRowPath;
  final ImportMode? osHoverAffordance;
  final int revision;

  FileTreeDropHost copyWith({
    String? osHoverRowPath,
    ImportMode? osHoverAffordance,
    bool clearOsHover = false,
    int? revision,
  }) {
    return FileTreeDropHost(
      ingest: ingest,
      cubit: cubit,
      osHoverRowPath: clearOsHover ? null : (osHoverRowPath ?? this.osHoverRowPath),
      osHoverAffordance: clearOsHover
          ? null
          : (osHoverAffordance ?? this.osHoverAffordance),
      revision: revision ?? this.revision,
    );
  }
}

/// Panel-level OS drop + scope for in-tree row targets.
class FileTreeDropRegion extends StatefulWidget {
  const FileTreeDropRegion({
    required this.cubit,
    required this.listScrollController,
    required this.child,
    this.importService,
    this.hostLocalFs,
    super.key,
  });

  final FileTreeCubit cubit;
  final ScrollController listScrollController;
  final Widget child;
  final WorkspaceImportService? importService;
  final Filesystem? hostLocalFs;

  @override
  State<FileTreeDropRegion> createState() => _FileTreeDropRegionState();
}

class _FileTreeDropRegionState extends State<FileTreeDropRegion> {
  late final WorkspaceImportService _importService;
  late final Filesystem _hostLocalFs;
  late final bool _ownsImportService;
  late FileTreeDropIngestor _ingestor;
  ConflictResolver? _conflictResolver;
  late FileTreeDropHost _host;
  var _busy = false;

  FileTreeDropIngestor _createIngestor() {
    return FileTreeDropIngestor(
      cubit: widget.cubit,
      importService: _importService,
      hostLocalFs: _hostLocalFs,
      onConflict: ({
        required String destPath,
        required bool sourceIsDirectory,
        required bool destIsDirectory,
        required bool typeMismatch,
        required int remainingConflicts,
      }) {
        final resolver = _conflictResolver;
        if (resolver == null) return Future.value(ConflictChoice.cancelAll);
        return resolver(
          destPath: destPath,
          sourceIsDirectory: sourceIsDirectory,
          destIsDirectory: destIsDirectory,
          typeMismatch: typeMismatch,
          remainingConflicts: remainingConflicts,
        );
      },
      isCopyModifierPressed: fileTreeCopyModifierPressed,
    );
  }

  @override
  void initState() {
    super.initState();
    _ownsImportService = widget.importService == null;
    _importService = widget.importService ?? WorkspaceImportService();
    _hostLocalFs = widget.hostLocalFs ?? LocalFilesystem();
    _ingestor = _createIngestor();
    _host = FileTreeDropHost(ingest: _ingest, cubit: widget.cubit);
  }

  @override
  void didUpdateWidget(covariant FileTreeDropRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit) {
      _ingestor = _createIngestor();
      _host = FileTreeDropHost(
        ingest: _ingest,
        cubit: widget.cubit,
        osHoverRowPath: _host.osHoverRowPath,
        osHoverAffordance: _host.osHoverAffordance,
        revision: _host.revision + 1,
      );
    }
  }

  @override
  void dispose() {
    if (_ownsImportService) {
      _importService.dispose();
    }
    super.dispose();
  }

  double get _scrollOffset {
    final controller = widget.listScrollController;
    if (!controller.hasClients) return 0;
    return controller.offset;
  }

  FileTreeDropHit _hitAt(
    Offset listLocal, {
    List<String> sourcePaths = const [],
  }) {
    final state = widget.cubit.state;
    final contentY = fileTreeDropContentY(
      listLocalY: listLocal.dy,
      scrollOffset: _scrollOffset,
    );
    return resolveFileTreePanelDropHit(
      contentY: contentY,
      visibleRows: state.visibleRows,
      rootPaths: state.rootPaths,
      pathContextFor: (path) => widget.cubit.fsFor(path).pathContext,
      sourcePaths: sourcePaths,
    );
  }

  String? _rowPathAt(Offset listLocal) {
    final rows = widget.cubit.state.visibleRows;
    if (rows.isEmpty) return null;
    final contentY = fileTreeDropContentY(
      listLocalY: listLocal.dy,
      scrollOffset: _scrollOffset,
    );
    final index = contentY < 0 ? -1 : (contentY / kFileTreeRowExtent).floor();
    if (index < 0 || index >= rows.length) return null;
    return rows[index].path;
  }

  void _updateOsHover(Offset? listLocal) {
    if (listLocal == null) {
      if (_host.osHoverRowPath != null || _host.osHoverAffordance != null) {
        setState(() {
          _host = _host.copyWith(
            clearOsHover: true,
            revision: _host.revision + 1,
          );
        });
      }
      return;
    }
    final hit = _hitAt(listLocal);
    final rowPath = hit.isValid ? _rowPathAt(listLocal) : null;
    final affordance = hit.isValid ? ImportMode.copy : null;
    if (rowPath == _host.osHoverRowPath &&
        affordance == _host.osHoverAffordance) {
      return;
    }
    setState(() {
      _host = FileTreeDropHost(
        ingest: _ingest,
        cubit: widget.cubit,
        osHoverRowPath: rowPath,
        osHoverAffordance: affordance,
        revision: _host.revision + 1,
      );
    });
  }

  Future<void> _onOsDrop(
    WorkspaceDragPayload payload,
    DropDoneDetails details,
  ) async {
    _updateOsHover(null);
    final hit = _hitAt(details.localPosition);
    if (!hit.isValid) {
      if (hit.rejectedReason == 'ontoSelf' && mounted) {
        showFileTreeImportRejectSelfToast(context);
      }
      return;
    }
    await _ingest(
      destDir: hit.destDir!,
      payload: payload,
      fromExternalOs: true,
    );
  }

  Future<void> _ingest({
    required String destDir,
    required WorkspaceDragPayload payload,
    required bool fromExternalOs,
  }) async {
    if (_busy || !mounted || payload.refs.isEmpty) return;
    _busy = true;
    final session = FileTreeImportConflictSession();
    _conflictResolver = session.resolver(context);
    try {
      final plan = await _ingestor.prepareAt(
        destDir: destDir,
        payload: payload,
        fromExternalOs: fromExternalOs,
      );
      if (!mounted) return;

      late final ImportSummary summary;
      if (shouldShowImportProgress(
        flattenedFileCount: plan.flattenedFileCount,
        maxFileBytes: plan.maxFileBytes,
        destIsLocal: plan.destIsLocal,
      )) {
        final cancelRequested = ValueNotifier(false);
        try {
          summary = await showFileTreeImportProgressDialog<ImportSummary>(
            context: context,
            progress: _importService.progress,
            cancelRequested: cancelRequested,
            task: _ingestor.runPrepared(
              plan,
              isCancelled: () => cancelRequested.value,
            ),
          );
        } finally {
          cancelRequested.dispose();
        }
      } else {
        summary = await _ingestor.runPrepared(plan, isCancelled: () => false);
      }

      if (mounted) {
        showFileTreeImportSummaryIfNeeded(context, summary);
      }
    } finally {
      _conflictResolver = null;
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FileTreeDropScope(
      host: _host,
      child: ExternalFileDropRegion(
        target: const NoopWorkspaceDropTarget(),
        onDropPayload: _onOsDrop,
        onDragPositionChanged: _updateOsHover,
        showPanelHighlight: false,
        child: widget.child,
      ),
    );
  }
}

/// Row highlight + copy/move label while a drop target is active.
class FileTreeDropHighlight extends StatelessWidget {
  const FileTreeDropHighlight({
    required this.active,
    required this.affordance,
    required this.child,
    super.key,
  });

  final bool active;
  final ImportMode? affordance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final label = affordance == ImportMode.move
        ? l10n.fileTreeImportDropMove
        : l10n.fileTreeImportDropCopy;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 2),
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
