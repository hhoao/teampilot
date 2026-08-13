import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot_search/teampilot_search.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/io/filesystem.dart';
import '../../../services/search/content_search_runner.dart';
import '../../../utils/debounce/debounce.dart';
import 'workspace_search_widgets.dart';

/// Content-search section for the search dialog's `content` filter: query +
/// regex/case chips, streaming file:line results. Not part of the `all`
/// filter — it is its own exclusive mode.
class WorkspaceSearchContentSection extends StatefulWidget {
  const WorkspaceSearchContentSection({
    required this.root,
    required this.fs,
    required this.onOpenFile,
    super.key,
  });

  final String root;
  final Filesystem fs;
  final void Function(String path) onOpenFile;

  @override
  State<WorkspaceSearchContentSection> createState() =>
      _WorkspaceSearchContentSectionState();
}

class _WorkspaceSearchContentSectionState
    extends State<WorkspaceSearchContentSection> {
  static const _debounceTag = 'workspace_search_dialog_content';
  static const _debounceDelay = Duration(milliseconds: 300);

  /// Result cap for the dialog's content search. The rows render in a
  /// shrink-wrapped [ListView.builder], which builds every row to compute its
  /// extent — uncapped matches (e.g. a broad `.*` regex over a large repo)
  /// would build thousands of rows per run. Both the Rust engine and the
  /// Dart fallback stop at this cap; the stream completes either way.
  static const _maxDialogContentResults = 500;

  final _controller = TextEditingController();
  final _results = <TpSearchMatch>[];
  bool _searching = false;

  /// True when [_results] hit the [_maxDialogContentResults] cap — the
  /// engines truncate silently, so this is detected by match count.
  bool _truncated = false;
  bool _isRegex = true;
  bool _caseSensitive = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _seq++;
    Debounces.cancel(_debounceTag);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    Debounces.debounce(_debounceTag, _debounceDelay, () {
      if (!mounted) return;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    final seq = ++_seq;
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results.clear();
        _truncated = false;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final matches = <TpSearchMatch>[];
    try {
      final runner = ContentSearchRunner(fs: widget.fs, root: widget.root);
      await for (final m in runner.run(TpSearchOptions(
        pattern: query,
        isRegex: _isRegex,
        caseSensitive: _caseSensitive,
        maxResults: _maxDialogContentResults,
      ))) {
        if (seq != _seq || !mounted) return;
        matches.add(m);
      }
    } on Object {
      if (seq != _seq || !mounted) return;
    }
    if (seq != _seq || !mounted) return;
    setState(() {
      _results
        ..clear()
        ..addAll(matches);
      _truncated = matches.length >= _maxDialogContentResults;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.workspaceSearchQueryHint,
                ),
              ),
            ),
            FilterChip(
              label: const Text('.*'),
              tooltip: l10n.workspaceSearchRegex,
              selected: _isRegex,
              onSelected: (v) {
                setState(() => _isRegex = v);
                unawaited(_run());
              },
            ),
            FilterChip(
              label: const Text('Aa'),
              tooltip: l10n.workspaceSearchCaseSensitive,
              selected: _caseSensitive,
              onSelected: (v) {
                setState(() => _caseSensitive = v);
                unawaited(_run());
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_searching)
          WorkspaceSearchStatusRow(label: l10n.workspaceSearchSearching)
        else if (query.isEmpty)
          WorkspaceSearchStatusRow(label: l10n.workspaceSearchEmptyHint)
        else if (_results.isEmpty)
          WorkspaceSearchStatusRow(label: l10n.workspaceSearchNoResults)
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length + (_truncated ? 1 : 0),
              itemBuilder: (context, i) {
                if (_truncated && i == _results.length) {
                  return WorkspaceSearchStatusRow(
                    label: l10n.workspaceSearchTruncated,
                  );
                }
                final m = _results[i];
                return WorkspaceSearchFileRow(
                  name: '${m.relativePath}:${m.lineNumber}',
                  query: query,
                  relativePath: m.lineText.trim(),
                  onTap: () => widget.onOpenFile(m.path),
                );
              },
            ),
          ),
      ],
    );
  }
}
