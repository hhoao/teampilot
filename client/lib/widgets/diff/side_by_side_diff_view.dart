import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/diff/diff_decoration_mapper.dart';
import '../../services/diff/diff_model.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/editor_platform/document_session.dart';
import '../../services/editor_platform/document_session_token_provider.dart';
import '../../services/editor_platform/editor_platform.dart';
import '../../services/editor_platform/editor_viewport_token_binder.dart';
import '../../theme/workspace_surface_layers.dart';
import 'diff_hunk_apply_gutter.dart';
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
    this.chrome = WorkspacePageChrome.workspace,
    this.writable = false,
    this.canonicalText = '',
    this.onCanonicalChanged,
    this.onApplyHunk,
    super.key,
  });

  final DiffResult result;

  /// Used for syntax highlighting (extension → language) on both panes.
  final String? filePath;

  /// Optional shared navigation controller (next/previous change).
  final DiffViewController? controller;

  /// Workspace surface chrome for editor backgrounds.
  final WorkspacePageChrome chrome;

  /// When true, the right pane is editable and shows [canonicalText] (no fillers).
  final bool writable;

  /// Working-tree text for the right pane when [writable].
  final String canonicalText;

  /// Called when the user edits the right pane while [writable].
  final ValueChanged<String>? onCanonicalChanged;

  /// Invoked when the user taps `>>` on a change block while [writable].
  final Future<void> Function(DiffResult result, DiffBlock block)? onApplyHunk;

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
  bool _suppressCanonicalNotify = false;
  double _lineHeightCache = 16;

  DocumentSession? _leftSession;
  DocumentSession? _rightSession;
  DocumentSessionTokenProvider? _leftTokenProvider;
  DocumentSessionTokenProvider? _rightTokenProvider;

  /// Bumped on every reopen so a stale async [_openSessions] call (superseded
  /// by a newer result before it finished opening) discards its sessions
  /// instead of publishing them.
  int _sessionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    _texts = buildDiffPaneTexts(_result.rows);
    _leftController = CodeLineEditingController.fromText(_texts.leftText);
    _rightController = CodeLineEditingController.fromText(_rightPaneText());
    _leftScroll = CodeScrollController();
    _rightScroll = CodeScrollController();
    _leftScroll.verticalScroller.addListener(_syncFromLeft);
    _rightScroll.verticalScroller.addListener(_syncFromRight);
    if (widget.writable) {
      _rightController.addListener(_onRightTextChanged);
    }
    widget.controller?.addListener(_onNavigate);
    _publishChangeCount();
    unawaited(_openSessions());
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
      _setRightPaneText(_rightPaneText());
      _publishChangeCount();
      unawaited(_openSessions());
    } else if (widget.writable &&
        oldWidget.canonicalText != widget.canonicalText) {
      _setRightPaneText(widget.canonicalText);
      unawaited(_openSessions());
    }
    if (oldWidget.writable != widget.writable) {
      if (widget.writable) {
        _rightController.addListener(_onRightTextChanged);
        _setRightPaneText(_rightPaneText());
      } else {
        _rightController.removeListener(_onRightTextChanged);
        _setRightPaneText(_texts.rightText);
      }
      unawaited(_openSessions());
    }
  }

  String _rightPaneText() =>
      widget.writable ? widget.canonicalText : _texts.rightText;

  void _setRightPaneText(String text) {
    if (_rightController.text == text) return;
    _suppressCanonicalNotify = true;
    _rightController.text = text;
    _suppressCanonicalNotify = false;
  }

  void _onRightTextChanged() {
    if (_suppressCanonicalNotify || !widget.writable) return;
    widget.onCanonicalChanged?.call(_rightController.text);
  }

  /// Opens fresh read-only [DocumentSession]s for the current left/right pane
  /// text and swaps them in once viewport coloring is ready. Never awaited by
  /// callers — a bumped [_sessionGeneration] lets an in-flight call from a
  /// superseded result discard its sessions on completion instead of racing
  /// with a newer one.
  Future<void> _openSessions() async {
    final generation = ++_sessionGeneration;
    final path = widget.filePath ?? 'untitled.txt';
    final leftText = _texts.leftText;
    final rightText = _rightPaneText();
    final registry = EditorPlatform.registry;
    final pool = EditorPlatform.workerPool;

    final left = DocumentSession(registry: registry, pool: pool);
    final right = DocumentSession(registry: registry, pool: pool);
    await left.open(path: path, text: leftText);
    await right.open(path: path, text: rightText);
    if (generation != _sessionGeneration) {
      left.dispose();
      right.dispose();
      return;
    }

    await left.colorizeAfterOpen(
      viewportEndLine: math.min(80, left.lineCount - 1),
    );
    await right.colorizeAfterOpen(
      viewportEndLine: math.min(80, right.lineCount - 1),
    );
    if (!mounted || generation != _sessionGeneration) {
      left.dispose();
      right.dispose();
      return;
    }

    final oldLeftSession = _leftSession;
    final oldRightSession = _rightSession;
    final oldLeftProvider = _leftTokenProvider;
    final oldRightProvider = _rightTokenProvider;
    setState(() {
      _leftSession = left;
      _rightSession = right;
      _leftTokenProvider = DocumentSessionTokenProvider(left);
      _rightTokenProvider = DocumentSessionTokenProvider(right);
    });
    oldLeftProvider?.dispose();
    oldRightProvider?.dispose();
    oldLeftSession?.dispose();
    oldRightSession?.dispose();
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
    if (widget.writable) {
      _rightController.removeListener(_onRightTextChanged);
    }
    _leftController.dispose();
    _rightController.dispose();
    _leftScroll.dispose();
    _rightScroll.dispose();
    // Invalidate any in-flight _openSessions() so it discards rather than
    // setState()s on a disposed widget.
    _sessionGeneration++;
    _leftTokenProvider?.dispose();
    _rightTokenProvider?.dispose();
    _leftSession?.dispose();
    _rightSession?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = diffColorsFor(cs);
    final decorations = buildDiffPaneDecorations(_result.rows, colors);
    final rightDecorations = widget.writable ? const <CodeLineDecoration>[] : decorations.right;
    final rightNumbers = widget.writable
        ? _canonicalLineNumbers(widget.canonicalText)
        : _texts.rightNumbers;
    final path = widget.filePath ?? 'untitled.txt';
    final shellSurface = cs.workspaceCardChrome(widget.chrome);
    final leftStyle = codeEditorStyleFor(
      context,
      path,
      backgroundColor: shellSurface,
      tokenProvider: _leftTokenProvider,
    );
    final rightStyle = codeEditorStyleFor(
      context,
      path,
      backgroundColor: shellSurface,
      tokenProvider: _rightTokenProvider,
    );
    _lineHeightCache = _lineHeight(leftStyle);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _pane(
            controller: _leftController,
            scroll: _leftScroll,
            decorations: decorations.left,
            numbers: _texts.leftNumbers,
            style: leftStyle,
            session: _leftSession,
          ),
        ),
        _ribbonGap(cs, colors, leftStyle),
        Expanded(
          child: _pane(
            controller: _rightController,
            scroll: _rightScroll,
            decorations: rightDecorations,
            numbers: rightNumbers,
            style: rightStyle,
            session: _rightSession,
            readOnly: !widget.writable,
          ),
        ),
        DiffOverviewRuler(
          blocks: _result.blocks,
          totalRows: _result.rows.length,
          scroll: _rightScroll,
          lineHeight: _lineHeightCache,
          topPadding: _kEditorTopPadding,
          trackColor: cs.workspaceSubtleSurface,
        ),
      ],
    );
  }

  Widget _ribbonGap(ColorScheme cs, DiffColors colors, CodeEditorStyle style) {
    final divider = VerticalDivider(
      width: 1,
      thickness: 1,
      color: cs.outlineVariant,
    );
    final lineHeight = _lineHeight(style);
    final gutterWidth = widget.writable ? 36.0 : 24.0;
    return Row(
      children: [
        divider,
        SizedBox(
          width: gutterWidth,
          child: ClipRect(
            child: ListenableBuilder(
              listenable: _leftScroll.verticalScroller,
              builder: (context, _) {
                final scroller = _leftScroll.verticalScroller;
                final offset = scroller.hasClients ? scroller.offset : 0.0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: DiffRibbonPainter(
                        scrollOffset: offset,
                        lineHeight: lineHeight,
                        topPadding: _kEditorTopPadding,
                        blocks: _result.blocks,
                        colors: colors,
                      ),
                    ),
                    if (widget.writable && widget.onApplyHunk != null)
                      DiffHunkApplyGutter(
                        blocks: _result.blocks,
                        scrollOffset: offset,
                        lineHeight: lineHeight,
                        topPadding: _kEditorTopPadding,
                        tooltip: context.l10n.diffApplyHunkTooltip,
                        onApply: (block) {
                          unawaited(widget.onApplyHunk!(_result, block));
                        },
                      ),
                  ],
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
    required DocumentSession? session,
    bool readOnly = true,
  }) {
    return CodeEditor(
      controller: controller,
      scrollController: scroll,
      readOnly: readOnly,
      showCursorWhenReadOnly: !readOnly,
      wordWrap: false,
      style: style,
      lineDecorations: decorations,
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return _DiffPaneLineNumbers(
              controller: editingController,
              notifier: notifier,
              session: session,
              numbers: numbers,
            );
          },
    );
  }
}

/// Gutter line numbers for one diff pane; keeps an [EditorViewportTokenBinder]
/// bound to [session] so the visible line band stays colored as the user
/// scrolls (same pattern as `FileEditorSurface`'s indicator wrapper).
class _DiffPaneLineNumbers extends StatefulWidget {
  const _DiffPaneLineNumbers({
    required this.controller,
    required this.notifier,
    required this.session,
    required this.numbers,
  });

  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final DocumentSession? session;
  final List<int?> numbers;

  @override
  State<_DiffPaneLineNumbers> createState() => _DiffPaneLineNumbersState();
}

class _DiffPaneLineNumbersState extends State<_DiffPaneLineNumbers> {
  EditorViewportTokenBinder? _binder;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_DiffPaneLineNumbers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.notifier != widget.notifier) {
      _bind();
    }
  }

  void _bind() {
    _binder?.dispose();
    final session = widget.session;
    _binder = session == null
        ? null
        : EditorViewportTokenBinder(
            session: session,
            notifier: widget.notifier,
          );
  }

  @override
  void dispose() {
    _binder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultCodeLineNumber(
      controller: widget.controller,
      notifier: widget.notifier,
      customLineIndex2Text: (lineIndex) {
        if (lineIndex < 0 || lineIndex >= widget.numbers.length) return '';
        final no = widget.numbers[lineIndex];
        return no == null ? '' : '$no';
      },
    );
  }
}

/// re-editor's default code-field top padding (`EdgeInsets.all(5)`); the diff
/// view uses no find bar, so this is the content top inset.
const double _kEditorTopPadding = 5;

List<int?> _canonicalLineNumbers(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.length > 1 && lines.last.isEmpty) {
    lines.removeLast();
  }
  return List<int?>.generate(lines.length, (i) => i + 1);
}

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
