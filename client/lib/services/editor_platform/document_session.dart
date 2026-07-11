import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../utils/logger.dart';
import 'language_pack.dart';
import 'language_registry.dart';
import 'token_span.dart';
import 'utf8_index_map.dart';
import 'worker_protocol.dart';

/// Loads a `highlights.scm` query source for an asset path. Injectable so unit
/// tests can bypass `rootBundle` (which needs a Flutter asset bundle).
typedef HighlightsLoader = Future<String> Function(String assetPath);

/// UI-side owner of one open document's syntax state.
///
/// A [DocumentSession] holds the source text, a [Utf8IndexMap] for code-unit ↔
/// byte conversion, a per-line token cache, and a serial channel to a pooled
/// tree-sitter worker that owns the actual parse tree. The UI isolate never
/// touches the tree: it sends ordered `open` / `edit` / `queryRange` / `dispose`
/// commands and applies the immutable token snapshots that come back.
///
/// It is a [ChangeNotifier] so a `CodeTokenProvider` (wired in a later task) can
/// repaint affected lines when new tokens arrive.
class DocumentSession extends ChangeNotifier {
  DocumentSession({
    required LanguageRegistry registry,
    required TsWorkerPool pool,
    String? sessionId,
    HighlightsLoader? highlightsLoader,
    Duration frameBudget = const Duration(milliseconds: 8),
  }) : _registry = registry,
       _pool = pool,
       _sessionId = sessionId ?? 'doc-${_sessionCounter++}',
       _highlightsLoader = highlightsLoader ?? rootBundle.loadString,
       _frameBudget = frameBudget;

  static int _sessionCounter = 0;

  final LanguageRegistry _registry;
  final TsWorkerPool _pool;
  final String _sessionId;
  final HighlightsLoader _highlightsLoader;
  final Duration _frameBudget;

  final Map<int, List<TokenSpan>> _tokensByLine = {};
  final Map<int, _PendingQuery> _pending = {};

  /// Frame-budget timers for in-flight `awaitResult` waits. Tracked so
  /// [dispose] can cancel them synchronously — a bare `Future.timeout` leaves a
  /// pending timer that survives widget teardown (and trips the test binding's
  /// `!timersPending` invariant) whenever a session is disposed before its
  /// worker reply arrives.
  final Set<Timer> _budgetTimers = {};

  Utf8IndexMap _indexMap = Utf8IndexMap('');
  List<int> _lineStarts = <int>[0];

  LanguagePack? _pack;
  String _highlightsQuery = '';
  TsSessionHandle? _handle;
  StreamSubscription<TsQueryResult>? _resultsSub;

  int _seq = 0;
  int _latestEditSeq = 0;
  int _requestId = 0;

  int? _viewportStartLine;
  int? _viewportEndLine;

  bool _opened = false;
  bool _disposed = false;

  /// Number of lines in the current document (always `>= 1`).
  int get lineCount => _lineStarts.length;

  /// Whether the resolved [LanguagePack] has a grammar/highlighter. Unknown
  /// extensions open as plain text: no worker, no tokens.
  bool get hasHighlighting => _pack != null;

  /// Resolves the language pack for [path], initializes local text state, and
  /// asks the worker to parse the document. Does **not** wait for tokens — call
  /// [colorizeAfterOpen] for viewport-first coloring.
  ///
  /// Re-opening an already-open session (e.g. the same `DocumentSession`
  /// reused for a different file) is supported: any previous worker
  /// attachment is disposed and its pending queries are cancelled first, so
  /// callers never need to `dispose()` between opens.
  Future<void> open({required String path, required String text}) async {
    if (_disposed) return;
    await _detachWorker();
    _pack = _registry.resolve(path);
    _indexMap = Utf8IndexMap(text);
    _lineStarts = _computeLineStarts(text);
    _tokensByLine.clear();
    _viewportStartLine = null;
    _viewportEndLine = null;
    _opened = true;
    final pack = _pack;
    if (pack == null) {
      // Plain text: no grammar, no worker.
      return;
    }
    String highlightsQuery;
    try {
      highlightsQuery = await _highlightsLoader(pack.highlightsAsset);
    } on Object catch (error, stackTrace) {
      appLogger.e(
        'DocumentSession: failed to load highlights asset '
        '${pack.highlightsAsset} for $path',
        error: error,
        stackTrace: stackTrace,
      );
      // Degrade to plain text rather than crashing the open.
      _pack = null;
      return;
    }
    if (_disposed) return;
    _highlightsQuery = highlightsQuery;
    final TsSessionHandle handle;
    try {
      handle = _pool.openSession(_sessionId);
    } on Object catch (error, stackTrace) {
      appLogger.e(
        'DocumentSession: failed to open worker session for $path',
        error: error,
        stackTrace: stackTrace,
      );
      _pack = null;
      return;
    }
    _handle = handle;
    _resultsSub = handle.results.listen(_onResult);
    final seq = ++_seq;
    _latestEditSeq = seq;
    handle.send(
      TsOpen(
        sessionId: _sessionId,
        seq: seq,
        grammarId: pack.grammarId,
        highlightsQuery: _highlightsQuery,
        utf8Bytes: _encode(text),
      ),
    );
  }

  /// Applies a code-unit range replacement, mirrors it to the worker as an
  /// incremental edit, and invalidates the token cache for the touched lines
  /// (keeping tokens for every other line). Re-tokenization of the dirty lines
  /// and the current viewport is enqueued but not awaited.
  void applyEdit({
    required int codeUnitStart,
    required int codeUnitDeleteCount,
    required String insert,
  }) {
    if (_disposed || !_opened) return;

    final startByte = _indexMap.byteOffsetForCodeUnit(codeUnitStart);
    final oldEndByte = _indexMap.byteOffsetForCodeUnit(
      codeUnitStart + codeUnitDeleteCount,
    );
    final oldStartLine = _lineForCodeUnit(codeUnitStart);
    final oldEndLine = _lineForCodeUnit(codeUnitStart + codeUnitDeleteCount);

    _indexMap.applyEdit(
      codeUnitStart: codeUnitStart,
      codeUnitDeleteCount: codeUnitDeleteCount,
      insert: insert,
    );
    _lineStarts = _computeLineStarts(_indexMap.text);

    final newEndCodeUnit = codeUnitStart + insert.length;
    final newEndLine = _lineForCodeUnit(newEndCodeUnit);
    final newEndByte = _indexMap.byteOffsetForCodeUnit(newEndCodeUnit);
    final lineDelta = newEndLine - oldEndLine;

    _remapTokenCacheForEdit(oldStartLine, oldEndLine, lineDelta);

    final pack = _pack;
    if (pack == null) {
      notifyListeners();
      return;
    }

    final seq = ++_seq;
    _latestEditSeq = seq;
    _handle?.send(
      TsEdit(
        sessionId: _sessionId,
        seq: seq,
        startByte: startByte,
        oldEndByte: oldEndByte,
        newEndByte: newEndByte,
        utf8Bytes: _encode(_indexMap.text),
      ),
    );

    var queryStart = oldStartLine;
    var queryEnd = newEndLine;
    final vpStart = _viewportStartLine;
    final vpEnd = _viewportEndLine;
    if (vpStart != null && vpEnd != null) {
      queryStart = queryStart < vpStart ? queryStart : vpStart;
      queryEnd = queryEnd > vpEnd ? queryEnd : vpEnd;
    }
    unawaited(ensureTokensForLines(queryStart, queryEnd, highPriority: true));
    notifyListeners();
  }

  /// Requests tokens for lines `[startLine, endLine]`.
  ///
  /// When [awaitResult] is true the call awaits the worker reply but only up to
  /// the frame budget (default 8ms); on timeout it returns and the tokens are
  /// applied whenever the reply eventually arrives — never flashing lines to
  /// unstyled. Already-cached lines are not re-queried.
  Future<void> ensureTokensForLines(
    int startLine,
    int endLine, {
    bool awaitResult = false,
    bool highPriority = false,
  }) async {
    if (_disposed || _pack == null) return;
    final count = lineCount;
    var start = startLine < 0 ? 0 : startLine;
    var end = endLine >= count ? count - 1 : endLine;
    if (start > end) return;

    if (highPriority) {
      _viewportStartLine = start;
      _viewportEndLine = end;
    }

    var needsQuery = false;
    for (var line = start; line <= end; line++) {
      if (!_tokensByLine.containsKey(line)) {
        needsQuery = true;
        break;
      }
    }
    if (!needsQuery) return;

    final requestId = ++_requestId;
    final seq = ++_seq;
    final startByte = _indexMap.byteOffsetForCodeUnit(_lineStarts[start]);
    final endByte = _indexMap.byteOffsetForCodeUnit(
      _lineEndCodeUnitExclusive(end),
    );

    final completer = Completer<void>();
    _pending[requestId] = _PendingQuery(
      completer: completer,
      startLine: start,
      endLine: end,
    );
    _handle?.send(
      TsQueryRange(
        sessionId: _sessionId,
        seq: seq,
        requestId: requestId,
        startByte: startByte,
        endByte: endByte,
        highPriority: highPriority,
      ),
    );

    if (!awaitResult) return;
    await _awaitWithinBudget(completer.future);
  }

  /// Awaits [future] but only up to [_frameBudget], using a self-owned timer we
  /// can cancel in [dispose]. On timeout we return and keep prior tokens;
  /// `_onResult` applies the reply whenever it eventually arrives.
  Future<void> _awaitWithinBudget(Future<void> future) async {
    final budget = Completer<void>();
    final timer = Timer(_frameBudget, () {
      if (!budget.isCompleted) budget.complete();
    });
    _budgetTimers.add(timer);
    try {
      await Future.any(<Future<void>>[future, budget.future]);
    } finally {
      timer.cancel();
      _budgetTimers.remove(timer);
    }
  }

  /// Viewport-first coloring after [open]: awaits the visible band, then fires a
  /// non-awaited background fill for the rest of the file.
  Future<void> colorizeAfterOpen({required int viewportEndLine}) async {
    if (_disposed || _pack == null) return;
    await ensureTokensForLines(
      0,
      viewportEndLine,
      awaitResult: true,
      highPriority: true,
    );
    final lastLine = lineCount - 1;
    if (viewportEndLine + 1 <= lastLine) {
      unawaited(ensureTokensForLines(viewportEndLine + 1, lastLine));
    }
  }

  /// Immutable token snapshot for [lineIndex]. Empty when the line is untokenized
  /// or the document is plain text.
  List<TokenSpan> tokensForLine(int lineIndex) {
    return _tokensByLine[lineIndex] ?? const <TokenSpan>[];
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Cancel budget timers and settle pending waits synchronously so no timer
    // outlives the widget tree (the async _detachWorker below only handles the
    // worker teardown, whose futures don't register as pending timers).
    for (final timer in _budgetTimers) {
      timer.cancel();
    }
    _budgetTimers.clear();
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) pending.completer.complete();
    }
    unawaited(_detachWorker());
    super.dispose();
  }

  /// Tears down the current worker attachment: sends `dispose` for the
  /// session's tree, closes the pool handle, cancels the results
  /// subscription, and completes (without applying) any in-flight queries.
  ///
  /// Called both from [dispose] and from [open] (to support clean re-open on
  /// an already-open session) — always safe to call when there is no
  /// attachment.
  Future<void> _detachWorker() async {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      handle.send(TsDispose(sessionId: _sessionId, seq: ++_seq));
      handle.close();
    }
    final sub = _resultsSub;
    _resultsSub = null;
    await sub?.cancel();
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) pending.completer.complete();
    }
    _pending.clear();
  }

  void _onResult(TsQueryResult result) {
    if (_disposed) return;
    final pending = _pending.remove(result.requestId);
    if (pending == null) return;

    // Stale: the worker computed this reply against an older edit than the
    // most recent one the UI has sent (per-command monotonic `seq`, echoed by
    // the worker as `TsQueryResult.editSeq`). Keep prior tokens.
    if (result.editSeq < _latestEditSeq) {
      if (!pending.completer.isCompleted) pending.completer.complete();
      return;
    }

    final perLine = <int, List<TokenSpan>>{};
    for (var line = pending.startLine;
        line <= pending.endLine && line < lineCount;
        line++) {
      perLine[line] = <TokenSpan>[];
    }
    for (final capture in result.captures) {
      _addCaptureToLines(perLine, capture, pending.startLine, pending.endLine);
    }
    perLine.forEach((line, spans) {
      spans.sort((a, b) => a.start.compareTo(b.start));
      _tokensByLine[line] = List<TokenSpan>.unmodifiable(spans);
    });

    if (!pending.completer.isCompleted) pending.completer.complete();
    notifyListeners();
  }

  void _addCaptureToLines(
    Map<int, List<TokenSpan>> perLine,
    TsByteCapture capture,
    int minLine,
    int maxLine,
  ) {
    final cuStart = _indexMap.codeUnitOffsetForByte(capture.startByte);
    final cuEnd = _indexMap.codeUnitOffsetForByte(capture.endByte);
    if (cuEnd <= cuStart) return;

    final firstLine = _lineForCodeUnit(cuStart);
    final lastLine = _lineForCodeUnit(cuEnd - 1);
    for (var line = firstLine; line <= lastLine; line++) {
      if (line < minLine || line > maxLine) continue;
      final lineStart = _lineStarts[line];
      final lineEnd = _lineContentEndExclusive(line);
      final clipStart = cuStart > lineStart ? cuStart : lineStart;
      final clipEnd = cuEnd < lineEnd ? cuEnd : lineEnd;
      if (clipEnd <= clipStart) continue;
      perLine.putIfAbsent(line, () => <TokenSpan>[]).add(
            TokenSpan(
              start: clipStart - lineStart,
              length: clipEnd - clipStart,
              scope: capture.name,
            ),
          );
    }
  }

  /// Rebuilds the line-indexed token cache after an edit: lines before the edit
  /// keep their tokens, the edited range is dropped (dirty), and lines below
  /// shift by [lineDelta] (for inserted/removed newlines).
  void _remapTokenCacheForEdit(
    int oldStartLine,
    int oldEndLine,
    int lineDelta,
  ) {
    if (_tokensByLine.isEmpty) return;
    final remapped = <int, List<TokenSpan>>{};
    _tokensByLine.forEach((line, spans) {
      if (line < oldStartLine) {
        remapped[line] = spans;
      } else if (line <= oldEndLine) {
        // Edited lines are invalidated.
      } else {
        remapped[line + lineDelta] = spans;
      }
    });
    _tokensByLine
      ..clear()
      ..addAll(remapped);
  }

  int _lineForCodeUnit(int codeUnit) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_lineStarts[mid] <= codeUnit) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  int _lineEndCodeUnitExclusive(int line) {
    if (line + 1 < _lineStarts.length) return _lineStarts[line + 1];
    return _indexMap.text.length;
  }

  int _lineContentEndExclusive(int line) {
    if (line + 1 < _lineStarts.length) return _lineStarts[line + 1] - 1;
    return _indexMap.text.length;
  }

  Uint8List _encode(String text) => Uint8List.fromList(utf8.encode(text));

  static List<int> _computeLineStarts(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        starts.add(i + 1);
      }
    }
    return starts;
  }
}

class _PendingQuery {
  _PendingQuery({
    required this.completer,
    required this.startLine,
    required this.endLine,
  });

  final Completer<void> completer;
  final int startLine;
  final int endLine;
}
