import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../services/diff/diff_decoration_mapper.dart';
import '../../services/diff/diff_model.dart';
import '../../services/editor/file_editor_theme.dart';
import 'diff_overview_ruler.dart';
import 'diff_ribbon_painter.dart';
import 'diff_view_controller.dart';

/// IDEA-style two-pane diff renderer: aligned old/new code with
/// add/remove/modify line bands, inline char highlights, syntax coloring,
/// synchronized vertical scrolling, and a connecting ribbon.
///
/// Pure renderer — it takes a pre-computed [DiffResult]; the diff source
/// (compare texts vs parse a git unified diff) is owned by the caller.
class SideBySideDiffView extends StatefulWidget {
  const SideBySideDiffView({
    required this.result,
    this.filePath,
    this.controller,
    super.key,
  });

  final DiffResult result;

  /// Used for syntax highlighting (extension → language) on both panes.
  final String? filePath;

  /// Optional shared navigation controller (next/previous change).
  final DiffViewController? controller;

  @override
  State<SideBySideDiffView> createState() => _SideBySideDiffViewState();
}

class _SideBySideDiffViewState extends State<SideBySideDiffView> {
  late final CodeLineEditingController _leftController;
  late final CodeLineEditingController _rightController;
  late final CodeScrollController _leftScroll;
  late final CodeScrollController _rightScroll;

  late DiffResult _result;
  late DiffPaneTexts _texts;
  bool _syncing = false;
  double _lineHeightCache = 16;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    _texts = buildDiffPaneTexts(_result.rows);
    _leftController = CodeLineEditingController.fromText(_texts.leftText);
    _rightController = CodeLineEditingController.fromText(_texts.rightText);
    _leftScroll = CodeScrollController();
    _rightScroll = CodeScrollController();
    _leftScroll.verticalScroller.addListener(_syncFromLeft);
    _rightScroll.verticalScroller.addListener(_syncFromRight);
    widget.controller?.addListener(_onNavigate);
    _publishChangeCount();
  }

  @override
  void didUpdateWidget(SideBySideDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onNavigate);
      widget.controller?.addListener(_onNavigate);
    }
    if (!identical(oldWidget.result, widget.result)) {
      _result = widget.result;
      _texts = buildDiffPaneTexts(_result.rows);
      _leftController.text = _texts.leftText;
      _rightController.text = _texts.rightText;
      _publishChangeCount();
    }
  }

  void _publishChangeCount() {
    final controller = widget.controller;
    if (controller == null) return;
    final count = _result.blocks.length;
    // Defer: the toolbar listening to the controller is a sibling built in the
    // same frame, so notifying now would mark it dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.changeCount = count;
    });
  }

  void _onNavigate() {
    final controller = widget.controller;
    if (controller == null) return;
    final index = controller.current;
    if (index < 0 || index >= _result.blocks.length) return;
    final scroller = _leftScroll.verticalScroller;
    if (!scroller.hasClients) return;
    // Land the change a couple of lines below the top for context.
    final startRow = _result.blocks[index].startRow;
    final target = (_kEditorTopPadding + (startRow - 2) * _lineHeightCache)
        .clamp(0.0, scroller.position.maxScrollExtent);
    scroller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncFromLeft() => _mirror(_leftScroll, _rightScroll);
  void _syncFromRight() => _mirror(_rightScroll, _leftScroll);

  void _mirror(CodeScrollController from, CodeScrollController to) {
    if (_syncing) return;
    final src = from.verticalScroller;
    final dst = to.verticalScroller;
    if (!src.hasClients || !dst.hasClients) return;
    final target = src.offset.clamp(0.0, dst.position.maxScrollExtent);
    if ((dst.offset - target).abs() < 0.5) return;
    _syncing = true;
    dst.jumpTo(target);
    _syncing = false;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onNavigate);
    _leftScroll.verticalScroller.removeListener(_syncFromLeft);
    _rightScroll.verticalScroller.removeListener(_syncFromRight);
    _leftController.dispose();
    _rightController.dispose();
    _leftScroll.dispose();
    _rightScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = diffColorsFor(cs);
    final decorations = buildDiffPaneDecorations(_result.rows, colors);
    final path = widget.filePath ?? '';
    final style = codeEditorStyleFor(context, path);
    _lineHeightCache = _lineHeight(style);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _pane(
            controller: _leftController,
            scroll: _leftScroll,
            decorations: decorations.left,
            numbers: _texts.leftNumbers,
            style: style,
          ),
        ),
        _ribbonGap(cs, colors, style),
        Expanded(
          child: _pane(
            controller: _rightController,
            scroll: _rightScroll,
            decorations: decorations.right,
            numbers: _texts.rightNumbers,
            style: style,
          ),
        ),
        DiffOverviewRuler(
          blocks: _result.blocks,
          totalRows: _result.rows.length,
          scroll: _rightScroll,
          lineHeight: _lineHeightCache,
          topPadding: _kEditorTopPadding,
        ),
      ],
    );
  }

  Widget _ribbonGap(ColorScheme cs, DiffColors colors, CodeEditorStyle style) {
    final divider =
        VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant);
    final lineHeight = _lineHeight(style);
    return Row(
      children: [
        divider,
        SizedBox(
          width: 24,
          child: ClipRect(
            child: ListenableBuilder(
              listenable: _leftScroll.verticalScroller,
              builder: (context, _) {
                final scroller = _leftScroll.verticalScroller;
                final offset = scroller.hasClients ? scroller.offset : 0.0;
                return CustomPaint(
                  painter: DiffRibbonPainter(
                    scrollOffset: offset,
                    lineHeight: lineHeight,
                    topPadding: _kEditorTopPadding,
                    blocks: _result.blocks,
                    colors: colors,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
        divider,
      ],
    );
  }

  Widget _pane({
    required CodeLineEditingController controller,
    required CodeScrollController scroll,
    required List<CodeLineDecoration> decorations,
    required List<int?> numbers,
    required CodeEditorStyle style,
  }) {
    return CodeEditor(
      controller: controller,
      scrollController: scroll,
      readOnly: true,
      showCursorWhenReadOnly: false,
      wordWrap: false,
      style: style,
      lineDecorations: decorations,
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return DefaultCodeLineNumber(
          controller: editingController,
          notifier: notifier,
          customLineIndex2Text: (lineIndex) {
            if (lineIndex < 0 || lineIndex >= numbers.length) return '';
            final no = numbers[lineIndex];
            return no == null ? '' : '$no';
          },
        );
      },
    );
  }
}

/// re-editor's default code-field top padding (`EdgeInsets.all(5)`); the diff
/// view uses no find bar, so this is the content top inset.
const double _kEditorTopPadding = 5;

/// Exact rendered line height, matching re-editor's internal TextPainter so the
/// ribbon aligns with the text.
double _lineHeight(CodeEditorStyle style) {
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

/// Builds the diff color palette from the active [ColorScheme]. Shared by the
/// side-by-side and unified views.
DiffColors diffColorsFor(ColorScheme cs) {
  const green = Color(0xFF2EA043);
  final red = cs.error;
  return DiffColors(
    addBand: green.withValues(alpha: 0.13),
    addInline: green.withValues(alpha: 0.34),
    removeBand: red.withValues(alpha: 0.12),
    removeInline: red.withValues(alpha: 0.30),
    fillerBand: cs.onSurface.withValues(alpha: 0.045),
    ribbonAdd: green.withValues(alpha: 0.22),
    ribbonRemove: red.withValues(alpha: 0.20),
    ribbonModify: cs.primary.withValues(alpha: 0.20),
  );
}
