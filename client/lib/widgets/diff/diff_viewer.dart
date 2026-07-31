import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/diff/diff_engine.dart';
import '../../services/diff/diff_model.dart';
import '../../services/diff/diff_options.dart';
import '../../services/diff/unified_diff_parser.dart';
import '../../theme/workspace_surface_layers.dart';
import 'diff_toolbar.dart';
import 'diff_view_controller.dart';
import 'side_by_side_diff_view.dart';
import 'unified_diff_view.dart';

/// Full diff viewer: a toolbar (layout switch, ignore-whitespace, change
/// navigation) over a side-by-side or unified diff body.
///
/// Owns the diff source. Construct with [DiffViewer.fromTexts] to compare two
/// strings (ignore-whitespace re-diffs locally), or [DiffViewer.fromUnifiedDiff]
/// to render a git unified diff (ignore-whitespace / full-context re-fetch via
/// `reloadDiff`, or toggles hidden when no reloader is given). Callers that
/// keep [initialFullContext] true must pass already-expanded diff text.
class DiffViewer extends StatefulWidget {
  const DiffViewer._({
    required this.initialResult,
    required this.resolve,
    required this.supportsFullContext,
    this.filePath,
    this.initialMode = DiffViewMode.unified,
    this.initialFullContext = true,
    this.chrome = WorkspacePageChrome.workspace,
    this.onOpenSource,
    this.onSwitchToFile,
    this.title,
    this.writable = false,
    this.canonicalText = '',
    this.onCanonicalChanged,
    this.onApplyHunk,
    this.isDirty = false,
    this.onSave,
    super.key,
  });

  factory DiffViewer.fromTexts({
    required String oldText,
    required String newText,
    String? filePath,
    DiffViewMode initialMode = DiffViewMode.unified,
    WorkspacePageChrome chrome = WorkspacePageChrome.workspace,
    VoidCallback? onOpenSource,
    VoidCallback? onSwitchToFile,
    String? title,
    bool writable = false,
    String canonicalText = '',
    ValueChanged<String>? onCanonicalChanged,
    Future<void> Function(DiffResult result, DiffBlock block)? onApplyHunk,
    bool isDirty = false,
    VoidCallback? onSave,
    Key? key,
  }) {
    return DiffViewer._(
      initialResult: computeLineDiff(oldText, newText),
      resolve: (ignoreWhitespace, fullContext) async => computeLineDiff(
        oldText,
        newText,
        options: DiffOptions(ignoreWhitespace: ignoreWhitespace),
      ),
      // Comparing full texts already shows every line.
      supportsFullContext: false,
      filePath: filePath,
      initialMode: initialMode,
      initialFullContext: false,
      chrome: chrome,
      onOpenSource: onOpenSource,
      onSwitchToFile: onSwitchToFile,
      title: title,
      writable: writable,
      canonicalText: canonicalText,
      onCanonicalChanged: onCanonicalChanged,
      onApplyHunk: onApplyHunk,
      isDirty: isDirty,
      onSave: onSave,
      key: key,
    );
  }

  factory DiffViewer.fromUnifiedDiff({
    required String diffText,
    String? filePath,
    Future<String?> Function(bool ignoreWhitespace, bool fullContext)?
    reloadDiff,
    DiffViewMode initialMode = DiffViewMode.unified,
    bool initialFullContext = true,
    WorkspacePageChrome chrome = WorkspacePageChrome.workspace,
    VoidCallback? onOpenSource,
    VoidCallback? onSwitchToFile,
    String? title,
    bool writable = false,
    String canonicalText = '',
    ValueChanged<String>? onCanonicalChanged,
    Future<void> Function(DiffResult result, DiffBlock block)? onApplyHunk,
    bool isDirty = false,
    VoidCallback? onSave,
    Key? key,
  }) {
    return DiffViewer._(
      initialResult: parseUnifiedDiffToResult(diffText),
      resolve: reloadDiff == null
          ? null
          : (ignoreWhitespace, fullContext) async {
              final text = await reloadDiff(ignoreWhitespace, fullContext);
              return parseUnifiedDiffToResult(text ?? '');
            },
      // Expanding context needs re-fetching the diff with more `-U` lines.
      supportsFullContext: reloadDiff != null,
      filePath: filePath,
      initialMode: initialMode,
      initialFullContext: initialFullContext,
      chrome: chrome,
      onOpenSource: onOpenSource,
      onSwitchToFile: onSwitchToFile,
      title: title,
      writable: writable,
      canonicalText: canonicalText,
      onCanonicalChanged: onCanonicalChanged,
      onApplyHunk: onApplyHunk,
      isDirty: isDirty,
      onSave: onSave,
      key: key,
    );
  }

  final DiffResult initialResult;

  /// Recomputes the diff for the given options, or null when re-diffing is
  /// unavailable (ignore-whitespace / full-context toggles hidden).
  final Future<DiffResult> Function(bool ignoreWhitespace, bool fullContext)?
  resolve;

  /// Whether the "show all lines" toggle is meaningful for this source.
  final bool supportsFullContext;

  final String? filePath;
  final DiffViewMode initialMode;
  final bool initialFullContext;

  /// Workspace surface chrome for shell/editor backgrounds.
  final WorkspacePageChrome chrome;

  /// Opens the underlying file in the editor; shown as a toolbar button. Hidden
  /// when null.
  final VoidCallback? onOpenSource;

  /// When set, shows File|Diff pill and switches to the file surface.
  final VoidCallback? onSwitchToFile;

  /// Optional surface title shown on the left of the toolbar.
  final String? title;

  /// When true, side-by-side mode exposes an editable right pane and apply gutter.
  final bool writable;

  /// Working-tree text for the editable right pane.
  final String canonicalText;

  final ValueChanged<String>? onCanonicalChanged;

  final Future<void> Function(DiffResult result, DiffBlock block)? onApplyHunk;

  final bool isDirty;
  final VoidCallback? onSave;

  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer> {
  final DiffViewController _controller = DiffViewController();
  late DiffViewMode _mode = widget.initialMode;
  late DiffResult _result = widget.initialResult;
  bool _ignoreWhitespace = false;
  late bool _fullContext =
      widget.supportsFullContext && widget.initialFullContext;
  var _bodyReady = false;

  @override
  void initState() {
    super.initState();
    // Callers that default [initialFullContext] must supply matching text
    // (e.g. git `-U1000000`). Do not auto-reload on mount — that doubled the
    // git/parse cost when opening from source control.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _bodyReady = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final resolve = widget.resolve;
    if (resolve == null) return;
    final result = await resolve(_ignoreWhitespace, _fullContext);
    if (!mounted) return;
    setState(() => _result = result);
  }

  void _setIgnoreWhitespace(bool value) {
    if (value == _ignoreWhitespace) return;
    setState(() => _ignoreWhitespace = value);
    unawaited(_reload());
  }

  void _setFullContext(bool value) {
    if (value == _fullContext) return;
    setState(() => _fullContext = value);
    unawaited(_reload());
  }

  Widget _buildBody(BuildContext context) {
    if (_result.rows.isEmpty) {
      return Center(
        child: Text(
          context.l10n.diffNoChanges,
          style: TpTextStyles.of(context).mutedMd,
        ),
      );
    }
    return switch (_mode) {
      DiffViewMode.sideBySide => SideBySideDiffView(
        result: _result,
        filePath: widget.filePath,
        controller: _controller,
        chrome: widget.chrome,
        writable: widget.writable,
        canonicalText: widget.canonicalText,
        onCanonicalChanged: widget.onCanonicalChanged,
        onApplyHunk: widget.onApplyHunk,
      ),
      DiffViewMode.unified => UnifiedDiffView(
        result: _result,
        filePath: widget.filePath,
        controller: _controller,
        chrome: widget.chrome,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiffToolbar(
          controller: _controller,
          mode: _mode,
          chrome: widget.chrome,
          onModeChanged: (m) => setState(() => _mode = m),
          ignoreWhitespace: _ignoreWhitespace,
          onIgnoreWhitespaceChanged: _setIgnoreWhitespace,
          showIgnoreWhitespace: widget.resolve != null,
          fullContext: _fullContext,
          onFullContextChanged: _setFullContext,
          showFullContext: widget.supportsFullContext,
          onOpenSource: widget.onOpenSource,
          onSwitchToFile: widget.onSwitchToFile,
          title: widget.title,
          isDirty: widget.isDirty,
          onSave: widget.onSave,
        ),
        Expanded(
          child: _bodyReady
              ? _buildBody(context)
              : const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        ),
      ],
    );
  }
}
