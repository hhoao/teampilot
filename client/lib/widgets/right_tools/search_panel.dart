import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot_search/teampilot_search.dart' show TpSearchOptions;

import '../../cubits/content_search/content_search_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/io/filesystem.dart';
import '../../services/search/content_search_runner.dart';
import '../../utils/debounce/debounce.dart';
import 'search_panel_results.dart';

/// Right-tools search tool: pattern + options + replace over the workspace
/// content search engines (Rust / Dart fallback).
class WorkspaceSearchPanel extends StatefulWidget {
  const WorkspaceSearchPanel({
    required this.workspaceId,
    required this.root,
    required this.fs,
    required this.focusRequest,
    this.onOpenResult,
    super.key,
  });

  final String workspaceId;
  final String root;
  final Filesystem fs;

  /// Bump to focus the query field (Ctrl+Shift+F).
  final ValueNotifier<int> focusRequest;

  /// Injectable open handler for tests; defaults to editor open + select line.
  final void Function(String path, int lineNumber)? onOpenResult;

  @override
  State<WorkspaceSearchPanel> createState() => _WorkspaceSearchPanelState();
}

class _WorkspaceSearchPanelState extends State<WorkspaceSearchPanel> {
  final _queryController = TextEditingController();
  final _replaceController = TextEditingController();
  final _includeController = TextEditingController();
  final _excludeController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isRegex = true;
  bool _caseSensitive = false;
  bool _useGitignore = true;

  ContentSearchCubit get _cubit => context.read<ContentSearchCubit>();

  /// Captured in [didChangeDependencies] so [dispose] can cancel the search
  /// without an unsafe ancestor lookup on a deactivated element.
  ContentSearchCubit? _cubitRef;

  @override
  void initState() {
    super.initState();
    widget.focusRequest.addListener(_onFocusRequest);
    _queryController.addListener(_onQueryChanged);
    _replaceController.addListener(_onReplaceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubitRef = context.read<ContentSearchCubit>();
  }

  @override
  void dispose() {
    widget.focusRequest.removeListener(_onFocusRequest);
    _queryController.removeListener(_onQueryChanged);
    _replaceController.removeListener(_onReplaceChanged);
    _queryController.dispose();
    _replaceController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    _focusNode.dispose();
    // Bump the search sequence so an in-flight stream bails out instead of
    // emitting after the provider closes this cubit on unmount.
    final cubit = _cubitRef;
    if (cubit != null && !cubit.isClosed) {
      cubit.cancel();
    }
    super.dispose();
  }

  void _onFocusRequest() => _focusNode.requestFocus();

  void _onQueryChanged() {
    Debounces.debounce(
      'workspace_search_panel',
      const Duration(milliseconds: 300),
      () {
        if (!mounted) return;
        _runSearch();
      },
    );
  }

  void _onReplaceChanged() {
    if (mounted) setState(() {});
  }

  TpSearchOptions get _options => TpSearchOptions(
    pattern: _queryController.text,
    isRegex: _isRegex,
    caseSensitive: _caseSensitive,
    useGitignore: _useGitignore,
    filesToInclude: _includeController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    filesToExclude: _excludeController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
  );

  void _runSearch() {
    if (_queryController.text.trim().isEmpty) {
      _cubit.clear();
      return;
    }
    _cubit.search(_options);
  }

  void _cancelSearch() => _cubit.cancel();

  Future<void> _confirmReplaceAll(String replacement) async {
    final l10n = context.l10n;
    final count = _cubit.state.files.fold<int>(
      0,
      (sum, f) => sum + f.lines.where((l) => !l.replaced).length,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.workspaceSearchReplaceAllTitle),
            const SizedBox(height: 16),
            Text(l10n.workspaceSearchReplaceAllMessage(count)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                TpButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.workspaceSearchReplace),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _cubit.replaceAll(replacement);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return BlocBuilder<ContentSearchCubit, ContentSearchState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TpInput(
                    controller: _queryController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: l10n.workspaceSearchQueryHint,
                      suffixIcon: state.searching
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _cancelSearch,
                              tooltip: l10n.workspaceSearchCancel,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      FilterChip(
                        label: Text(l10n.workspaceSearchRegex),
                        selected: _isRegex,
                        onSelected: (v) => setState(() {
                          _isRegex = v;
                          _runSearch();
                        }),
                      ),
                      FilterChip(
                        label: Text(l10n.workspaceSearchCaseSensitive),
                        selected: _caseSensitive,
                        onSelected: (v) => setState(() {
                          _caseSensitive = v;
                          _runSearch();
                        }),
                      ),
                      FilterChip(
                        label: Text(l10n.workspaceSearchGitignore),
                        selected: _useGitignore,
                        onSelected: (v) => setState(() {
                          _useGitignore = v;
                          _runSearch();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TpInput(
                    controller: _includeController,
                    decoration: InputDecoration(
                      hintText: l10n.workspaceSearchIncludeHint,
                    ),
                    onChanged: (_) => Debounces.debounce(
                      'workspace_search_panel_globs',
                      const Duration(milliseconds: 400),
                      () {
                        if (!mounted) return;
                        _runSearch();
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  TpInput(
                    controller: _excludeController,
                    decoration: InputDecoration(
                      hintText: l10n.workspaceSearchExcludeHint,
                    ),
                    onChanged: (_) => Debounces.debounce(
                      'workspace_search_panel_globs',
                      const Duration(milliseconds: 400),
                      () {
                        if (!mounted) return;
                        _runSearch();
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TpInput(
                          controller: _replaceController,
                          decoration: InputDecoration(
                            hintText: l10n.workspaceSearchReplaceHint,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TpButton(
                        onPressed: _replaceController.text.isEmpty
                            ? null
                            : () => _confirmReplaceAll(_replaceController.text),
                        child: Text(l10n.workspaceSearchReplaceAll),
                      ),
                    ],
                  ),
                  if (state.replacedCount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.workspaceSearchReplacedCount(state.replacedCount!),
                        style: styles.smColored(cs.primary),
                      ),
                    ),
                ],
              ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  l10n.workspaceSearchError,
                  style: styles.smColored(cs.error),
                ),
              ),
            Expanded(
              child: SearchPanelResults(
                files: state.files,
                query: _queryController.text,
                truncated: state.truncated,
                backendLabel: _backendLabel(),
                replacement: _replaceController.text,
                onOpenResult: (path, line) => _openResult(context, path, line),
                onReplaceSingle: (path, replacement) =>
                    _cubit.replaceSingle(path, replacement),
              ),
            ),
          ],
        );
      },
    );
  }

  String _backendLabel() =>
      ContentSearchRunner(fs: widget.fs, root: widget.root).backendLabel;

  void _openResult(BuildContext context, String path, int lineNumber) {
    final handler = widget.onOpenResult;
    if (handler != null) {
      handler(path, lineNumber);
      return;
    }
    final editor = context.read<EditorCubit>();
    editor.openFile(widget.workspaceId, path, fs: widget.fs);
    editor.selectLines(widget.workspaceId, path, startLine: lineNumber);
  }
}
