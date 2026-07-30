import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/services/file_tree/file_tree_visible_rows.dart';
import 'package:teampilot/services/file_tree_import/file_tree_drop_hit_test.dart';
import 'package:teampilot/services/file_tree_import/file_tree_drop_ingestor.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/progress_activity/file_tree_import_activity_adapter.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/workspace_dnd/workspace_drop_target.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:teampilot/widgets/file_tree/file_tree_import_dialogs.dart';
import 'package:teampilot/widgets/progress_activity/progress_activity_detail_dialog.dart';
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

enum FileTreeDropAcceptAction { ingest, rejectSelf, ignore }

FileTreeDropAcceptAction resolveFileTreeDropAcceptAction(FileTreeDropHit hit) {
  if (hit.isValid) return FileTreeDropAcceptAction.ingest;
  if (hit.rejectedReason == 'ontoSelf') {
    return FileTreeDropAcceptAction.rejectSelf;
  }
  return FileTreeDropAcceptAction.ignore;
}

/// OS hover chrome: row when over a row; dest + panel overlay on empty area.
({String? rowPath, bool panelHighlight}) resolveOsHoverHighlight({
  required FileTreeDropHit hit,
  required String? rowUnderPointer,
}) {
  if (!hit.isValid) {
    return (rowPath: null, panelHighlight: false);
  }
  if (rowUnderPointer != null) {
    return (rowPath: rowUnderPointer, panelHighlight: false);
  }
  return (rowPath: hit.destDir, panelHighlight: true);
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
        host.osHoverPanelHighlight != oldWidget.host.osHoverPanelHighlight ||
        host.revision != oldWidget.host.revision;
  }
}

class FileTreeDropHost {
  FileTreeDropHost({
    required this.ingest,
    required this.cubit,
    this.osHoverRowPath,
    this.osHoverAffordance,
    this.osHoverPanelHighlight = false,
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
  final bool osHoverPanelHighlight;
  final int revision;

  FileTreeDropHost copyWith({
    String? osHoverRowPath,
    ImportMode? osHoverAffordance,
    bool? osHoverPanelHighlight,
    bool clearOsHover = false,
    int? revision,
  }) {
    return FileTreeDropHost(
      ingest: ingest,
      cubit: cubit,
      osHoverRowPath: clearOsHover
          ? null
          : (osHoverRowPath ?? this.osHoverRowPath),
      osHoverAffordance: clearOsHover
          ? null
          : (osHoverAffordance ?? this.osHoverAffordance),
      osHoverPanelHighlight: clearOsHover
          ? false
          : (osHoverPanelHighlight ?? this.osHoverPanelHighlight),
      revision: revision ?? this.revision,
    );
  }
}

/// Panel-level OS drop + scope for in-tree row targets.
class FileTreeDropRegion extends StatefulWidget {
  const FileTreeDropRegion({
    required this.cubit,
    required this.listScrollController,
    required this.workspaceId,
    required this.child,
    this.importService,
    this.hostLocalFs,
    super.key,
  });

  final FileTreeCubit cubit;
  final ScrollController listScrollController;
  final String workspaceId;
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
        osHoverPanelHighlight: _host.osHoverPanelHighlight,
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
      if (_host.osHoverRowPath != null ||
          _host.osHoverAffordance != null ||
          _host.osHoverPanelHighlight) {
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
    final highlight = resolveOsHoverHighlight(
      hit: hit,
      rowUnderPointer: hit.isValid ? _rowPathAt(listLocal) : null,
    );
    final affordance = hit.isValid ? ImportMode.copy : null;
    if (highlight.rowPath == _host.osHoverRowPath &&
        affordance == _host.osHoverAffordance &&
        highlight.panelHighlight == _host.osHoverPanelHighlight) {
      return;
    }
    setState(() {
      _host = FileTreeDropHost(
        ingest: _ingest,
        cubit: widget.cubit,
        osHoverRowPath: highlight.rowPath,
        osHoverAffordance: affordance,
        osHoverPanelHighlight: highlight.panelHighlight,
        revision: _host.revision + 1,
      );
    });
  }

  List<String> _sourcePaths(WorkspaceDragPayload payload) => [
    for (final ref in payload.refs) ref.nativePath,
  ];

  Future<void> _handleResolvedDrop({
    required FileTreeDropHit hit,
    required WorkspaceDragPayload payload,
    required bool fromExternalOs,
  }) async {
    switch (resolveFileTreeDropAcceptAction(hit)) {
      case FileTreeDropAcceptAction.ingest:
        await _ingest(
          destDir: hit.destDir!,
          payload: payload,
          fromExternalOs: fromExternalOs,
        );
      case FileTreeDropAcceptAction.rejectSelf:
        if (mounted) showFileTreeImportRejectSelfToast(context);
      case FileTreeDropAcceptAction.ignore:
        break;
    }
  }

  Future<void> _onOsDrop(
    WorkspaceDragPayload payload,
    DropDoneDetails details,
  ) async {
    _updateOsHover(null);
    final hit = _hitAt(
      details.localPosition,
      sourcePaths: _sourcePaths(payload),
    );
    await _handleResolvedDrop(
      hit: hit,
      payload: payload,
      fromExternalOs: true,
    );
  }

  Future<void> _onInTreePanelDrop(
    DragTargetDetails<WorkspaceDragPayload> details,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final local = box != null && box.hasSize
        ? box.globalToLocal(details.offset)
        : details.offset;
    final hit = _hitAt(local, sourcePaths: _sourcePaths(details.data));
    await _handleResolvedDrop(
      hit: hit,
      payload: details.data,
      fromExternalOs: false,
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

      final l10n = context.l10n;
      final progressCubit = context.read<ProgressActivityCubit>();
      final adapter = FileTreeImportActivityAdapter(
        cubit: progressCubit,
        importService: _importService,
      );
      final summary = await adapter.runTracked(
        plan: plan,
        title: l10n.fileTreeImportProgressTitle,
        workspaceId: widget.workspaceId,
        historyMessageFor: (result) => l10n.fileTreeImportSummary(
          result.succeeded,
          result.skipped,
          result.failed,
        ),
        onActivityStarted: (activityId) {
          if (!mounted) return;
          progressCubit.setDetailOpen(activityId, true);
          unawaited(
            showProgressActivityDetailDialog(
              context,
              activityId: activityId,
            ),
          );
        },
        runImport: ({required isCancelled}) =>
            _ingestor.runPrepared(plan, isCancelled: isCancelled),
      );

      if (mounted) {
        showFileTreeImportSummaryIfNeeded(context, summary);
      }
    } catch (error, stackTrace) {
      AppLogger.instance.e(
        'File tree import failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.fileTreeImportSummary(0, 0, 1),
          variant: TpToastVariant.error,
        );
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
        child: DragTarget<WorkspaceDragPayload>(
          onWillAcceptWithDetails: (details) {
            return details.data.kind == DragPayloadKind.workspaceFile &&
                details.data.refs.isNotEmpty;
          },
          onAcceptWithDetails: (details) {
            unawaited(_onInTreePanelDrop(details));
          },
          builder: (context, candidates, rejected) {
            final inTreeEmptyHover =
                candidates.isNotEmpty && candidates.first != null;
            final showPanel =
                inTreeEmptyHover || _host.osHoverPanelHighlight;
            ImportMode? affordance;
            if (inTreeEmptyHover) {
              final payload = candidates.first!;
              final sourcePath = payload.refs.first.nativePath;
              final destDir =
                  widget.cubit.state.rootPath.isNotEmpty
                  ? widget.cubit.state.rootPath
                  : sourcePath;
              final sameFs = fileTreePathsShareFilesystem(
                sourceFs: widget.cubit.fsFor(sourcePath),
                destFs: widget.cubit.fsFor(destDir),
                sourceWorkContext: widget.cubit.workContextFor(sourcePath),
                destWorkContext: widget.cubit.workContextFor(destDir),
              );
              affordance = resolveFileTreeImportMode(
                fromExternalOs: false,
                sameFs: sameFs,
                copyModifier: fileTreeCopyModifierPressed(),
              );
            } else {
              affordance = _host.osHoverAffordance;
            }
            return Stack(
              fit: StackFit.passthrough,
              children: [
                widget.child,
                if (showPanel)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: FileTreeDropHighlight(
                        active: true,
                        affordance: affordance,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
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
