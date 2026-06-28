import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../cubits/editor_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/editor/file_editor_theme.dart';
import '../theme/app_text_styles.dart';
import '../services/editor/file_editor_toolbar.dart';
import '../services/editor/file_editor_tab_close.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/debounce/debounce.dart';
import 'app_dialog.dart';
import 'file_editor/file_editor_tab.dart';

class FileEditorPanel extends StatelessWidget {
  const FileEditorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FileEditorTabBar(),
          const Divider(height: 1),
          const Expanded(child: _FileEditorBody()),
        ],
      ),
    );
  }
}

class _FileEditorTabBar extends StatelessWidget {
  const _FileEditorTabBar();

  @override
  Widget build(BuildContext context) {
    final tabModel = context.select<EditorCubit, _EditorTabBarModel>(
      (c) => _EditorTabBarModel.from(c.state),
    );
    if (tabModel.openPaths.isEmpty) {
      return const SizedBox.shrink();
    }

    final editor = context.read<EditorCubit>();
    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabModel.openPaths.length,
        itemBuilder: (context, index) {
          final path = tabModel.openPaths[index];
          final selected = index == tabModel.activeIndex;
          final dirty = tabModel.dirtyPaths.contains(path);
          final name = p.basename(path);

          return FileEditorTab(
            fileName: name,
            filePath: path,
            selected: selected,
            dirty: dirty,
            onTap: () => editor.selectFile(index),
            onClose: () => FileEditorTabClose.closeAt(context, index),
            onCloseOthers: () => FileEditorTabClose.closeOthers(context, index),
            onCloseRight: () => FileEditorTabClose.closeRight(context, index),
          );
        },
      ),
    );
  }
}

class _FileEditorBody extends StatelessWidget {
  const _FileEditorBody();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<EditorCubit, EditorState, _EditorBodyModel>(
      selector: _EditorBodyModel.from,
      builder: (context, model) {
        final l10n = context.l10n;
        final path = model.activePath;

        if (path == null) {
          return Center(child: Text(l10n.editorNoFileOpen));
        }

        if (model.isLoading) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final loadError = model.loadError;
        if (loadError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.editorPanelErrorMessage(loadError),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final editor = context.read<EditorCubit>();
        final controller = editor.controllerFor(path);
        if (controller == null) {
          return Center(child: Text(l10n.editorNotReady));
        }

        return CodeEditor(
          key: editor.editorKeyFor(path) ?? ValueKey(path),
          controller: controller,
          readOnly: model.readOnly,
          toolbarController: const FileEditorContextMenuController(),
          style: codeEditorStyleFor(context, path),
          wordWrap: false,
          indicatorBuilder:
              (context, editingController, chunkController, notifier) {
                return DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                );
              },
        );
      },
    );
  }
}

/// Single app-level host for the draggable floating file editor.
///
/// Mounted exactly once, above the workspace-tab `IndexedStack` — never inside a
/// per-tab `ChatWorkbench`. The editor's controller and per-file [GlobalKey]
/// (see `EditorCubit`) are app-global, so building it in more than one mounted
/// tab raises "Duplicate GlobalKey", and reparenting it across the tabs' nested
/// `LayoutBuilder`s throws "RenderFlex was mutated in performLayout". A single
/// stable host avoids both: the keyed editor lives in one `LayoutBuilder` and is
/// only ever swapped within its own subtree (on file switch / open / close).
///
/// Returns an empty box when no file is open, so it is safe to keep in the tree.
class WorkspaceFloatingEditor extends StatelessWidget {
  const WorkspaceFloatingEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final hasOpen = context.select<EditorCubit, bool>(
      (c) => c.state.hasOpenFiles,
    );
    if (!hasOpen) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _FloatingEditorWindow(
              areaWidth: constraints.maxWidth,
              areaHeight: constraints.maxHeight,
            ),
          ],
        );
      },
    );
  }
}

class _FloatingEditorWindow extends StatefulWidget {
  const _FloatingEditorWindow({
    required this.areaWidth,
    required this.areaHeight,
  });

  final double areaWidth;
  final double areaHeight;

  @override
  State<_FloatingEditorWindow> createState() => _FloatingEditorWindowState();
}

class _FloatingEditorWindowState extends State<_FloatingEditorWindow> {
  /// Gap between the floating panel and the terminal/workbench edges.
  static const _margin = 2.0;

  /// Initial open only — not a resize cap.
  static const _defaultWidthFraction = 0.5;

  Offset? _position;
  Size? _size;

  double _maxWidth(double maxW) => maxW - _margin * 2;

  double _maxHeight(double maxH) => maxH - _margin * 2;

  Size _defaultSize(double maxW, double maxH) {
    return Size(_maxWidth(maxW) * _defaultWidthFraction, _maxHeight(maxH));
  }

  Offset _defaultPosition(double maxW, Size size) {
    // Right half-pane: terminal stays visible on the left.
    return Offset(maxW - size.width - _margin, _margin);
  }

  void _applyResizePan({
    required _ResizeEdges edges,
    required Offset delta,
    required double maxW,
    required double maxH,
  }) {
    final limitW = _maxWidth(maxW);
    final limitH = _maxHeight(maxH);
    final defaultSize = _defaultSize(maxW, maxH);
    final currentSize = _size ?? defaultSize;
    final currentPos = _position ?? _defaultPosition(maxW, currentSize);

    var w = currentSize.width;
    var h = currentSize.height;
    var x = currentPos.dx;
    var y = currentPos.dy;

    if (edges.left) {
      final newW = (w - delta.dx).clamp(0.0, limitW);
      x += w - newW;
      w = newW;
    } else if (edges.right) {
      w = (w + delta.dx).clamp(0.0, limitW);
    }

    if (edges.top) {
      final newH = (h - delta.dy).clamp(0.0, limitH);
      y += h - newH;
      h = newH;
    } else if (edges.bottom) {
      h = (h + delta.dy).clamp(0.0, limitH);
    }

    setState(() {
      _size = Size(w, h);
      _position = Offset(
        x.clamp(_margin, maxW - w - _margin),
        y.clamp(_margin, maxH - h - _margin),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activePath = context.select<EditorCubit, String?>(
      (c) => c.state.activePath,
    );

    final maxW = widget.areaWidth;
    final maxH = widget.areaHeight;
    final limitW = _maxWidth(maxW);
    final limitH = _maxHeight(maxH);
    final defaultSize = _defaultSize(maxW, maxH);

    final size = Size(
      (_size ?? defaultSize).width.clamp(0.0, limitW),
      (_size ?? defaultSize).height.clamp(0.0, limitH),
    );
    final position = Offset(
      (_position ?? _defaultPosition(maxW, size)).dx.clamp(
        _margin,
        maxW - size.width - _margin,
      ),
      (_position ?? _defaultPosition(maxW, size)).dy.clamp(
        _margin,
        maxH - size.height - _margin,
      ),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: Material(
        elevation: 16,
        shadowColor: cs.shadow.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.25,
        ),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        color: cs.workspaceCard,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FloatingTitleBar(
                  path: activePath,
                  onDragUpdate: (delta) {
                    setState(() {
                      final base = _position ?? _defaultPosition(maxW, size);
                      _size = size;
                      _position = Offset(
                        (base.dx + delta.dx).clamp(
                          _margin,
                          maxW - size.width - _margin,
                        ),
                        (base.dy + delta.dy).clamp(
                          _margin,
                          maxH - size.height - _margin,
                        ),
                      );
                    });
                  },
                  onClose: () => _closeFloatingWindow(context),
                ),
                const Expanded(child: FileEditorPanel()),
              ],
            ),
            _FloatingWindowResizeLayer(
              onPanUpdate: (edges, delta) => _applyResizePan(
                edges: edges,
                delta: delta,
                maxW: maxW,
                maxH: maxH,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closeFloatingWindow(BuildContext context) async {
    final l10n = context.l10n;
    final editor = context.read<EditorCubit>();
    final dirty = editor.state.openPaths.where(editor.state.isDirty).toList();
    if (dirty.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AppDialog(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(title: l10n.editorUnsavedChangesTitle),
              const SizedBox(height: 16),
              Text(l10n.editorUnsavedChangesDiscardMultiple(dirty.length)),
              AppDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.editorDiscard),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (discard != true || !context.mounted) return;
    }
    while (editor.state.openPaths.isNotEmpty) {
      editor.closeFile(0, force: true);
    }
  }
}

class _ResizeEdges {
  const _ResizeEdges({
    this.left = false,
    this.right = false,
    this.top = false,
    this.bottom = false,
  });

  final bool left;
  final bool right;
  final bool top;
  final bool bottom;

  MouseCursor get cursor {
    if ((left && top) || (right && bottom)) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }
    if ((right && top) || (left && bottom)) {
      return SystemMouseCursors.resizeUpRightDownLeft;
    }
    if (left || right) return SystemMouseCursors.resizeLeftRight;
    if (top || bottom) return SystemMouseCursors.resizeUpDown;
    return SystemMouseCursors.basic;
  }
}

/// Transparent hit targets on window edges and corners (desktop-style resize).
class _FloatingWindowResizeLayer extends StatelessWidget {
  const _FloatingWindowResizeLayer({required this.onPanUpdate});

  static const _hit = 7.0;
  static const _corner = 14.0;
  static const _inset = 8.0;

  final void Function(_ResizeEdges edges, Offset delta) onPanUpdate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _ResizeHandle(
          edges: const _ResizeEdges(top: true),
          onPanUpdate: onPanUpdate,
          top: 0,
          left: _inset,
          right: _inset,
          height: _hit,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(bottom: true),
          onPanUpdate: onPanUpdate,
          bottom: 0,
          left: _inset,
          right: _inset,
          height: _hit,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(left: true),
          onPanUpdate: onPanUpdate,
          left: 0,
          top: _inset,
          bottom: _inset,
          width: _hit,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(right: true),
          onPanUpdate: onPanUpdate,
          right: 0,
          top: _inset,
          bottom: _inset,
          width: _hit,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(left: true, top: true),
          onPanUpdate: onPanUpdate,
          top: 0,
          left: 0,
          width: _corner,
          height: _corner,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(right: true, top: true),
          onPanUpdate: onPanUpdate,
          top: 0,
          right: 0,
          width: _corner,
          height: _corner,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(left: true, bottom: true),
          onPanUpdate: onPanUpdate,
          bottom: 0,
          left: 0,
          width: _corner,
          height: _corner,
        ),
        _ResizeHandle(
          edges: const _ResizeEdges(right: true, bottom: true),
          onPanUpdate: onPanUpdate,
          bottom: 0,
          right: 0,
          width: _corner,
          height: _corner,
        ),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.edges,
    required this.onPanUpdate,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
  });

  final _ResizeEdges edges;
  final void Function(_ResizeEdges edges, Offset delta) onPanUpdate;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: edges.cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) => onPanUpdate(edges, details.delta),
        ),
      ),
    );
  }
}

class _FloatingTitleBar extends StatelessWidget {
  const _FloatingTitleBar({
    required this.path,
    required this.onDragUpdate,
    required this.onClose,
  });

  final String? path;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final titleModel = context.select<EditorCubit, _FloatingTitleModel>(
      (c) => _FloatingTitleModel.from(c.state, path),
    );
    final title = titleModel.path ?? '';

    return GestureDetector(
      onPanUpdate: (details) => onDragUpdate(details.delta),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: cs.workspaceInset,
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.drag_indicator,
              size: context.appIconSizes.md,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.isEmpty ? l10n.editorTitle : p.basename(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.of(context).body,
              ),
            ),
            if (titleModel.showDirtyActions) ...[
              IconButton(
                tooltip: l10n.editorSave,
                iconSize: context.appIconSizes.md,
                visualDensity: VisualDensity.compact,
                onPressed: throttledAsync(
                  'file_editor_save',
                  () => context.read<EditorCubit>().saveActive(),
                ),
                icon: Icon(Icons.check, color: cs.secondary),
              ),
              IconButton(
                tooltip: l10n.editorRevertChanges,
                iconSize: context.appIconSizes.md,
                visualDensity: VisualDensity.compact,
                onPressed: throttledOnPressed(
                  'file_editor_revert',
                  context.read<EditorCubit>().revertActive,
                ),
                icon: Icon(
                  Icons.undo,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                ),
              ),
            ],
            IconButton(
              tooltip: l10n.editorClose,
              iconSize: context.appIconSizes.md,
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _EditorTabBarModel {
  const _EditorTabBarModel({
    required this.openPaths,
    required this.activeIndex,
    required this.dirtyPaths,
  });

  factory _EditorTabBarModel.from(EditorState state) {
    return _EditorTabBarModel(
      openPaths: state.openPaths,
      activeIndex: state.activeIndex,
      dirtyPaths: state.dirtyPaths,
    );
  }

  final List<String> openPaths;
  final int activeIndex;
  final Set<String> dirtyPaths;

  @override
  bool operator ==(Object other) {
    return other is _EditorTabBarModel &&
        activeIndex == other.activeIndex &&
        dirtyPaths == other.dirtyPaths &&
        _listEquals(openPaths, other.openPaths);
  }

  @override
  int get hashCode => Object.hash(activeIndex, dirtyPaths, Object.hashAll(openPaths));
}

@immutable
class _EditorBodyModel {
  const _EditorBodyModel({
    required this.activePath,
    required this.isLoading,
    required this.loadError,
    required this.readOnly,
  });

  factory _EditorBodyModel.from(EditorState state) {
    final path = state.activePath;
    return _EditorBodyModel(
      activePath: path,
      isLoading: path != null && state.loadingPaths.contains(path),
      loadError: path == null ? null : state.errorByPath[path],
      readOnly: path != null && state.readOnlyPaths.contains(path),
    );
  }

  final String? activePath;
  final bool isLoading;
  final String? loadError;
  final bool readOnly;

  @override
  bool operator ==(Object other) {
    return other is _EditorBodyModel &&
        activePath == other.activePath &&
        isLoading == other.isLoading &&
        loadError == other.loadError &&
        readOnly == other.readOnly;
  }

  @override
  int get hashCode => Object.hash(activePath, isLoading, loadError, readOnly);
}

@immutable
class _FloatingTitleModel {
  const _FloatingTitleModel({
    required this.path,
    required this.showDirtyActions,
  });

  factory _FloatingTitleModel.from(EditorState state, String? path) {
    final dirty = path != null && state.dirtyPaths.contains(path);
    final readOnly = path != null && state.readOnlyPaths.contains(path);
    return _FloatingTitleModel(
      path: path,
      showDirtyActions: dirty && !readOnly,
    );
  }

  final String? path;
  final bool showDirtyActions;

  @override
  bool operator ==(Object other) {
    return other is _FloatingTitleModel &&
        path == other.path &&
        showDirtyActions == other.showDirtyActions;
  }

  @override
  int get hashCode => Object.hash(path, showDirtyActions);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
