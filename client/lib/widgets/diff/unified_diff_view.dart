import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../services/diff/diff_decoration_mapper.dart';
import '../../services/diff/diff_model.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../theme/workspace_surface_layers.dart';
import 'diff_overview_ruler.dart';
import 'diff_view_controller.dart';
import 'side_by_side_diff_view.dart' show diffColorsFor;

/// Single-column unified diff renderer: context lines plus removed/added lines
/// (modify rows render as an old line then a new line), with the same line bands
/// and inline char highlights as the side-by-side view.
///
/// Pure renderer — takes a pre-computed [DiffResult].
class UnifiedDiffView extends StatefulWidget {
  const UnifiedDiffView({
    required this.result,
    this.filePath,
    this.controller,
    this.chrome = WorkspacePageChrome.workspace,
    super.key,
  });

  final DiffResult result;
  final String? filePath;
  final DiffViewController? controller;
  final WorkspacePageChrome chrome;

  @override
  State<UnifiedDiffView> createState() => _UnifiedDiffViewState();
}

class _UnifiedDiffViewState extends State<UnifiedDiffView> {
  late final CodeLineEditingController _controller;
  late final CodeScrollController _scroll;
  late List<DiffRow> _rows;
  late UnifiedPane _pane;
  double _lineHeightCache = 16;

  @override
  void initState() {
    super.initState();
    _build();
    _controller = CodeLineEditingController.fromText(_pane.text);
    _scroll = CodeScrollController();
    widget.controller?.addListener(_onNavigate);
    _publishChangeCount();
  }

  @override
  void didUpdateWidget(UnifiedDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onNavigate);
      widget.controller?.addListener(_onNavigate);
    }
    if (!identical(oldWidget.result, widget.result)) {
      _build();
      _controller.text = _pane.text;
      _publishChangeCount();
    }
  }

  void _build() {
    _rows = widget.result.rows;
    // Text/numbers/block starts are color-independent; decorations are rebuilt
    // with the real palette in build().
    _pane = buildUnifiedPane(_rows, _transparentColors);
  }

  void _publishChangeCount() {
    final controller = widget.controller;
    if (controller == null) return;
    final count = _pane.blocks.length;
    // Defer so the sibling toolbar isn't marked dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.changeCount = count;
    });
  }

  void _onNavigate() {
    final controller = widget.controller;
    if (controller == null) return;
    final index = controller.current;
    if (index < 0 || index >= _pane.blocks.length) return;
    final scroller = _scroll.verticalScroller;
    if (!scroller.hasClients) return;
    final startLine = _pane.blocks[index].startRow;
    final target = (5 + (startLine - 2) * _lineHeightCache)
        .clamp(0.0, scroller.position.maxScrollExtent);
    scroller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onNavigate);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = widget.filePath ?? '';
    final shellSurface = cs.workspaceCardChrome(widget.chrome);
    final style = codeEditorStyleFor(
      context,
      path,
      backgroundColor: shellSurface,
    );
    _lineHeightCache = _unifiedLineHeight(style);

    // Rebuild decorations with real theme colors against the cached structure.
    final pane = buildUnifiedPane(_rows, diffColorsFor(cs));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CodeEditor(
            controller: _controller,
            scrollController: _scroll,
            readOnly: true,
            showCursorWhenReadOnly: false,
            wordWrap: false,
            style: style,
            lineDecorations: pane.decorations,
            indicatorBuilder:
                (context, editingController, chunkController, notifier) {
              return DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                customLineIndex2Text: (lineIndex) {
                  if (lineIndex < 0 || lineIndex >= pane.numbers.length) {
                    return '';
                  }
                  final no = pane.numbers[lineIndex];
                  return no == null ? '' : '$no';
                },
              );
            },
          ),
        ),
        DiffOverviewRuler(
          blocks: pane.blocks,
          totalRows: pane.lineCount,
          scroll: _scroll,
          lineHeight: _lineHeightCache,
          topPadding: 5,
          trackColor: cs.workspaceSubtleSurface,
        ),
      ],
    );
  }
}

double _unifiedLineHeight(CodeEditorStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: '0',
      style: TextStyle(
        fontSize: style.fontSize,
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        height: style.fontHeight,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.preferredLineHeight;
}

const DiffColors _transparentColors = DiffColors(
  addBand: Color(0x00000000),
  addInline: Color(0x00000000),
  removeBand: Color(0x00000000),
  removeInline: Color(0x00000000),
  fillerBand: Color(0x00000000),
  ribbonAdd: Color(0x00000000),
  ribbonRemove: Color(0x00000000),
  ribbonModify: Color(0x00000000),
);
