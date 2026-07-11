import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../services/diff/diff_decoration_mapper.dart';
import '../../services/diff/diff_model.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/editor_platform/document_session.dart';
import '../../services/editor_platform/document_session_token_provider.dart';
import '../../services/editor_platform/editor_platform.dart';
import '../../services/editor_platform/editor_viewport_token_binder.dart';
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

  DocumentSession? _session;
  DocumentSessionTokenProvider? _tokenProvider;

  /// Bumped on every reopen so a stale async [_openSession] call (superseded
  /// by a newer result before it finished opening) discards its session
  /// instead of publishing it.
  int _sessionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _build();
    _controller = CodeLineEditingController.fromText(_pane.text);
    _scroll = CodeScrollController();
    widget.controller?.addListener(_onNavigate);
    _publishChangeCount();
    unawaited(_openSession());
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
      unawaited(_openSession());
    }
  }

  void _build() {
    _rows = widget.result.rows;
    // Text/numbers/block starts are color-independent; decorations are rebuilt
    // with the real palette in build().
    _pane = buildUnifiedPane(_rows, _transparentColors);
  }

  /// Opens a fresh read-only [DocumentSession] for the current unified pane
  /// text and swaps it in once viewport coloring is ready. Never awaited by
  /// callers — a bumped [_sessionGeneration] lets an in-flight call from a
  /// superseded result discard its session on completion instead of racing
  /// with a newer one.
  Future<void> _openSession() async {
    final generation = ++_sessionGeneration;
    final path = widget.filePath ?? 'untitled.txt';
    final text = _pane.text;

    final session = DocumentSession(
      registry: EditorPlatform.registry,
      pool: EditorPlatform.workerPool,
    );
    await session.open(path: path, text: text);
    if (generation != _sessionGeneration) {
      session.dispose();
      return;
    }

    await session.colorizeAfterOpen(
      viewportEndLine: math.min(80, session.lineCount - 1),
    );
    if (!mounted || generation != _sessionGeneration) {
      session.dispose();
      return;
    }

    final oldSession = _session;
    final oldProvider = _tokenProvider;
    setState(() {
      _session = session;
      _tokenProvider = DocumentSessionTokenProvider(session);
    });
    oldProvider?.dispose();
    oldSession?.dispose();
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
    final target = (5 + (startLine - 2) * _lineHeightCache).clamp(
      0.0,
      scroller.position.maxScrollExtent,
    );
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
    // Invalidate any in-flight _openSession() so it discards rather than
    // setState()s on a disposed widget.
    _sessionGeneration++;
    _tokenProvider?.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = widget.filePath ?? 'untitled.txt';
    final shellSurface = cs.workspaceCardChrome(widget.chrome);
    final style = codeEditorStyleFor(
      context,
      path,
      backgroundColor: shellSurface,
      tokenProvider: _tokenProvider,
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
                  return _UnifiedLineNumbers(
                    controller: editingController,
                    notifier: notifier,
                    session: _session,
                    numbers: pane.numbers,
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

/// Gutter line numbers for the unified pane; keeps an
/// [EditorViewportTokenBinder] bound to [session] so the visible line band
/// stays colored as the user scrolls (same pattern as `FileEditorSurface`'s
/// indicator wrapper).
class _UnifiedLineNumbers extends StatefulWidget {
  const _UnifiedLineNumbers({
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
  State<_UnifiedLineNumbers> createState() => _UnifiedLineNumbersState();
}

class _UnifiedLineNumbersState extends State<_UnifiedLineNumbers> {
  EditorViewportTokenBinder? _binder;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_UnifiedLineNumbers oldWidget) {
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
