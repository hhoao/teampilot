import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot_search/teampilot_search.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/search/multi_root_content_search.dart';
import '../../../utils/debounce/debounce.dart';
import 'workspace_search_widgets.dart';

/// One content hit tagged with the slice it came from.
typedef _ContentHit = (ContentSearchSlice slice, TpSearchMatch match);

/// One render row of the results list: a group header (multi-slice only), a
/// match row, or a per-slice error row.
typedef _Row = ({
  String? header,
  _ContentHit? hit,
  String? sliceError,
});

/// Content-search section for the search dialog's `content` filter: query +
/// regex/case chips, streaming file:line results over every workspace slice.
/// Not part of the `all` filter — it is its own exclusive mode.
class WorkspaceSearchContentSection extends StatefulWidget {
  const WorkspaceSearchContentSection({
    required this.slices,
    required this.onOpenFile,
    super.key,
  });

  /// One slice per searched root; each runs its own engine-backed runner via
  /// [MultiRootContentSearch], so a failing root never disturbs the others.
  final List<ContentSearchSlice> slices;
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
  final _results = <_ContentHit>[];
  bool _searching = false;

  /// True when any slice hit the [_maxDialogContentResults] cap — the engines
  /// truncate silently, so this is detected by per-slice match count.
  bool _truncated = false;

  /// True after a run failed on every slice (e.g. an invalid regex); renders
  /// the global error row instead of per-slice results.
  bool _error = false;

  /// Per-slice failures of an otherwise-successful run: root → label. Each
  /// entry renders its own error row after the match list.
  final _sliceErrors = <String, String>{};

  bool _isRegex = true;
  bool _caseSensitive = false;
  int _seq = 0;

  /// The active multi-root runner; cancelled on dispose and before each new
  /// run so every Rust walker stops promptly.
  MultiRootContentSearch? _search;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _seq++;
    _search?.cancel();
    _search = null;
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
    _search?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results.clear();
        _truncated = false;
        _error = false;
        _sliceErrors.clear();
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = false;
    });
    final hits = <_ContentHit>[];
    final sliceErrors = <String, String>{};
    final counts = <String, int>{};
    var anyMatch = false;
    final search = MultiRootContentSearch(slices: widget.slices);
    _search = search;
    try {
      await for (final event in search.run(TpSearchOptions(
        pattern: query,
        isRegex: _isRegex,
        caseSensitive: _caseSensitive,
        maxResults: _maxDialogContentResults,
      ))) {
        if (seq != _seq || !mounted) return;
        if (event.isError) {
          sliceErrors[event.slice.root] = event.slice.label;
          continue;
        }
        anyMatch = true;
        counts.update(
          event.slice.root,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
        hits.add((event.slice, event.match!));
      }
    } on Object {
      if (seq != _seq || !mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(hits);
        _truncated = false;
        _error = true;
        _sliceErrors.clear();
        _searching = false;
      });
      return;
    }
    if (seq != _seq || !mounted) return;
    // Group per slice: events interleave across the concurrent runners, so
    // the hits are re-ordered into slice order before rendering. Dart's
    // List.sort is unstable, so equal-comparing hits would scramble — group
    // by root instead, which preserves each slice's arrival order.
    final byRoot = <String, List<_ContentHit>>{};
    for (final hit in hits) {
      byRoot.putIfAbsent(hit.$1.root, () => []).add(hit);
    }
    final ordered = <_ContentHit>[
      for (final slice in widget.slices) ...?byRoot.remove(slice.root),
      // Slices not in the configured list (defensive) keep their arrival
      // order at the end.
      for (final remaining in byRoot.values) ...remaining,
    ];
    setState(() {
      _results
        ..clear()
        ..addAll(ordered);
      _sliceErrors
        ..clear()
        ..addAll(sliceErrors);
      _truncated = counts.values.any((c) => c >= _maxDialogContentResults);
      _error =
          !anyMatch &&
          widget.slices.isNotEmpty &&
          sliceErrors.length == widget.slices.length;
      _searching = false;
    });
  }

  /// Flat rows for the results list: a group header whenever the slice's root
  /// changes (only when more than one slice is searched — a single slice
  /// stays header-less), then one row per hit, then a per-slice error row.
  List<_Row> _buildRows() {
    final showHeaders = widget.slices.length > 1;
    final rows = <_Row>[];
    String? lastRoot;
    for (final hit in _results) {
      if (showHeaders && hit.$1.root != lastRoot) {
        lastRoot = hit.$1.root;
        rows.add((header: hit.$1.label, hit: null, sliceError: null));
      }
      rows.add((header: null, hit: hit, sliceError: null));
    }
    for (final label in _sliceErrors.values) {
      rows.add((header: null, hit: null, sliceError: label));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _controller.text.trim();
    final rows = _buildRows();
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
        else if (_error)
          WorkspaceSearchStatusRow(label: l10n.workspaceSearchError)
        else if (rows.isEmpty)
          WorkspaceSearchStatusRow(label: l10n.workspaceSearchNoResults)
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length + (_truncated ? 1 : 0),
              itemBuilder: (context, i) {
                if (_truncated && i == rows.length) {
                  return WorkspaceSearchStatusRow(
                    label: l10n.workspaceSearchTruncated,
                  );
                }
                final row = rows[i];
                final header = row.header;
                if (header != null) {
                  return WorkspaceSearchSectionHeader(label: header);
                }
                final sliceError = row.sliceError;
                if (sliceError != null) {
                  return WorkspaceSearchStatusRow(
                    label: l10n.workspaceSearchSliceError(sliceError),
                  );
                }
                final m = row.hit!.$2;
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
