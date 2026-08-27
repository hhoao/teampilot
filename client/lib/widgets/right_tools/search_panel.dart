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
import '../find/find_bar_widgets.dart';
import 'search_panel_form.dart';
import 'search_panel_results.dart';

/// Right-tools search tool styled like the VS Code search view: a search row
/// with inline option toggles, an expandable replace row, a `...` details
/// section (globs + gitignore), and collapsible file-group results over the
/// workspace content search engines (Rust / Dart fallback).
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
  /// Result cap for the panel. The Rust engine stops at this cap (the
  /// truncation footer is derived by the cubit from the cap); the lazy
  /// [SearchPanelResults] list stays bounded.
  static const _maxPanelResults = 2000;

  final _queryController = TextEditingController();
  final _replaceController = TextEditingController();
  final _includeController = TextEditingController();
  final _excludeController = TextEditingController();
  final _focusNode = FocusNode();
  final _replaceFocusNode = FocusNode();
  final _includeFocusNode = FocusNode();
  final _excludeFocusNode = FocusNode();
  bool _isRegex = true;
  bool _caseSensitive = false;
  bool _useGitignore = true;
  bool _showReplace = false;
  bool _showDetails = false;
  final Set<String> _collapsedPaths = {};
  late final Debouncer _searchDebouncer;
  late final Debouncer _globDebouncer;

  ContentSearchCubit get _cubit => context.read<ContentSearchCubit>();

  /// Captured in [didChangeDependencies] so [dispose] can cancel the search
  /// without an unsafe ancestor lookup on a deactivated element.
  ContentSearchCubit? _cubitRef;

  @override
  void initState() {
    super.initState();
    _searchDebouncer = Debouncer(
      tag: 'workspace_search_panel_${identityHashCode(this)}',
      duration: const Duration(milliseconds: 300),
    );
    _globDebouncer = Debouncer(
      tag: 'workspace_search_panel_globs_${identityHashCode(this)}',
      duration: const Duration(milliseconds: 400),
    );
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
    _replaceFocusNode.dispose();
    _includeFocusNode.dispose();
    _excludeFocusNode.dispose();
    _searchDebouncer.dispose();
    _globDebouncer.dispose();
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
    _searchDebouncer.call(_runSearch);
  }

  void _onReplaceChanged() {
    if (mounted) setState(() {});
  }

  TpSearchOptions get _options => TpSearchOptions(
    pattern: _queryController.text.trim(),
    isRegex: _isRegex,
    caseSensitive: _caseSensitive,
    useGitignore: _useGitignore,
    maxResults: _maxPanelResults,
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

  /// Non-default filters keep the `...` toggle highlighted, like VS Code.
  bool get _hasActiveFilters =>
      _includeController.text.trim().isNotEmpty ||
      _excludeController.text.trim().isNotEmpty ||
      !_useGitignore;

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
        final query = _queryController.text.trim();
        final pendingCount = state.files.fold<int>(
          0,
          (sum, f) => sum + f.lines.where((l) => !l.replaced).length,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SearchPanelChevron(
                        expanded: _showReplace,
                        onTap: () =>
                            setState(() => _showReplace = !_showReplace),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FindField(
                                    controller: _queryController,
                                    focusNode: _focusNode,
                                    hint: l10n.workspaceSearchQueryHint,
                                    toggles: [
                                      FindToggleButton(
                                        iconAsset: FindBarIcons.caseSensitive,
                                        tooltip: l10n.editorFindMatchCase,
                                        checked: _caseSensitive,
                                        onTap: () => setState(() {
                                          _caseSensitive = !_caseSensitive;
                                          _runSearch();
                                        }),
                                      ),
                                      FindToggleButton(
                                        iconAsset: FindBarIcons.regexp,
                                        tooltip: l10n.editorFindUseRegex,
                                        checked: _isRegex,
                                        onTap: () => setState(() {
                                          _isRegex = !_isRegex;
                                          _runSearch();
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                                if (state.searching) ...[
                                  const SizedBox(width: 4),
                                  FindActionButton(
                                    icon: Icons.close,
                                    tooltip: l10n.workspaceSearchCancel,
                                    onTap: _cancelSearch,
                                  ),
                                ],
                              ],
                            ),
                            if (_showReplace) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: FindField(
                                      controller: _replaceController,
                                      focusNode: _replaceFocusNode,
                                      hint: l10n.workspaceSearchReplaceHint,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  FindActionButton(
                                    key: const ValueKey('search-replace-all'),
                                    assetPath: FindBarIcons.replaceAll,
                                    tooltip: l10n.editorFindReplaceAll,
                                    enabled:
                                        _replaceController.text.isNotEmpty &&
                                        pendingCount > 0,
                                    onTap: () => _confirmReplaceAll(
                                      _replaceController.text,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SearchPanelDetailsToggle(
                      expanded: _showDetails,
                      highlighted: _hasActiveFilters,
                      onTap: () => setState(() => _showDetails = !_showDetails),
                    ),
                  ),
                  if (_showDetails) ...[
                    const SizedBox(height: 4),
                    SearchPanelDetailsSection(
                      includeController: _includeController,
                      includeFocusNode: _includeFocusNode,
                      excludeController: _excludeController,
                      excludeFocusNode: _excludeFocusNode,
                      useGitignore: _useGitignore,
                      onGlobChanged: (_) => _globDebouncer.call(_runSearch),
                      onGitignoreChanged: (v) => setState(() {
                        _useGitignore = v;
                        _runSearch();
                      }),
                    ),
                  ],
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
            if (query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.searching
                            ? l10n.workspaceSearchSearching
                            : state.files.isEmpty
                            ? ''
                            : l10n.workspaceSearchResultSummary(
                                pendingCount,
                                state.files.length,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.mutedSm,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_backendLabel(), style: styles.mutedSm),
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
                query: query,
                truncated: state.truncated,
                replacement: _replaceController.text,
                collapsedPaths: _collapsedPaths,
                onToggleGroup: (path) => setState(() {
                  if (!_collapsedPaths.add(path)) _collapsedPaths.remove(path);
                }),
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
