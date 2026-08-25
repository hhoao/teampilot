import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tp_markdown/tp_markdown.dart';

const int kMarkdownPreviewFindDebounceMs = 150;

/// Find state for the markdown preview pane.
///
/// Owns debounced query handling over [MarkdownSearchIndex], the hit list +
/// active index, and the highlight context handed to the preview view. The
/// index lifecycle is keyed on document identity: a new [MarkdownDocument]
/// instance rebuilds the projection lazily on the next scan.
class MarkdownPreviewFindController extends ChangeNotifier {
  Timer? _debounce;
  MarkdownDocument? _document;
  MarkdownSearchIndex? _index;
  MarkdownDocument? _indexedFor; // identity guard

  int _generation = 0;
  String _query = '';
  bool _caseSensitive = false;
  bool _regex = false;
  bool _hasError = false;
  List<MarkdownSearchHit> _hits = const [];
  int _activeIndex = -1;
  bool _open = false;

  /// Whether the find bar is visible.
  bool get open => _open;

  set open(bool value) {
    if (_open == value) return;
    _open = value;
    notifyListeners();
  }

  String get query => _query;

  bool get caseSensitive => _caseSensitive;

  bool get regex => _regex;

  /// Whether the last scan attempt failed (e.g. invalid regex).
  bool get hasError => _hasError;

  List<MarkdownSearchHit> get hits => _hits;

  /// Index of the active hit, -1 when none.
  int get activeIndex => _activeIndex;

  /// Highlight ranges for the current hits, null when there is nothing to
  /// paint.
  MarkdownHighlightContext? get highlights =>
      _hits.isEmpty || _index == null
          ? null
          : MarkdownSearchHighlightContext.of(
              _index!,
              _hits,
              activeOrdinal: _activeIndex,
            );

  MarkdownDocument? get document => _document;

  /// Container backing [hit], or null when out of range / no index.
  MarkdownSearchContainer? containerOf(MarkdownSearchHit hit) {
    final index = _index;
    if (index == null ||
        hit.container < 0 ||
        hit.container >= index.containers.length) {
      return null;
    }
    return index.containers[hit.container];
  }

  /// `'current/total'`, `'<cap>+'` when capped at [kMarkdownSearchMaxHits],
  /// empty when there are no hits.
  String counterLabel() {
    if (_hits.isEmpty) return '';
    final current = '${_activeIndex + 1}';
    final total = _hits.length >= kMarkdownSearchMaxHits
        ? '$kMarkdownSearchMaxHits+'
        : '${_hits.length}';
    return '$current/$total';
  }

  void openFind() => open = true;

  void close() {
    _debounce?.cancel();
    _debounce = null;
    _query = '';
    _hasError = false;
    _hits = const [];
    _activeIndex = -1;
    if (_open) _open = false;
    notifyListeners();
  }

  void setDocument(MarkdownDocument doc) {
    if (identical(_document, doc)) return;
    _document = doc;
    _index = null;
    _indexedFor = null;
    if (_open && _query.isNotEmpty) {
      _runScan();
    }
  }

  void search(String value) {
    _query = value;
    _debounce?.cancel();
    if (_query.isEmpty) {
      _generation++;
      _hasError = false;
      _hits = const [];
      _activeIndex = -1;
      notifyListeners();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: kMarkdownPreviewFindDebounceMs),
      _runScan,
    );
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _runScan();
  }

  void toggleRegex() {
    _regex = !_regex;
    _runScan();
  }

  void next() {
    if (_hits.isEmpty) return;
    _activeIndex = (_activeIndex + 1) % _hits.length;
    notifyListeners();
  }

  void previous() {
    if (_hits.isEmpty) return;
    _activeIndex = (_activeIndex - 1 + _hits.length) % _hits.length;
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _hits.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void _runScan() {
    final doc = _document;
    if (!_open || doc == null) return;
    _debounce?.cancel();
    _debounce = null;
    final generation = ++_generation;
    final index = _indexFor(doc);
    List<MarkdownSearchHit> hits;
    var errored = false;
    try {
      hits = index.search(
        MarkdownSearchQuery(
          pattern: _query,
          caseSensitive: _caseSensitive,
          regex: _regex,
        ),
      );
    } on MarkdownSearchException {
      // Invalid regex: surface error state instead of crashing (chat
      // precedent).
      hits = const [];
      errored = true;
    }
    if (generation != _generation) return; // stale result guard
    _hasError = errored;
    _hits = hits;
    _activeIndex = hits.isEmpty ? -1 : 0;
    notifyListeners();
  }

  MarkdownSearchIndex _indexFor(MarkdownDocument doc) {
    if (!identical(_indexedFor, doc) || _index == null) {
      _index = MarkdownSearchIndex.of(doc);
      _indexedFor = doc;
    }
    return _index!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
