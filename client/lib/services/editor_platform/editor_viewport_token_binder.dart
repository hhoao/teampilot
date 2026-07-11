import 'dart:async';

import 'package:re_editor/re_editor.dart';

import 'document_session.dart';

/// Bridges re-editor's visible-line range to a [DocumentSession]'s viewport
/// token requests.
///
/// re-editor publishes a [CodeIndicatorValue] on its indicator notifier every
/// time the rendered paragraphs change (scroll, resize, edit). Each
/// [CodeLineRenderParagraph] carries its line [CodeLineRenderParagraph.index],
/// so the min/max of the current paragraphs is the visible line band. On every
/// change we ask the session to (high-priority) colorize that band; the session
/// itself dedupes already-cached lines and tracks the viewport for edit
/// refreshes.
class EditorViewportTokenBinder {
  EditorViewportTokenBinder({
    required DocumentSession session,
    required CodeIndicatorValueNotifier notifier,
  })  : _session = session,
        _notifier = notifier {
    _notifier.addListener(_onIndicatorChanged);
    _onIndicatorChanged();
  }

  final DocumentSession _session;
  final CodeIndicatorValueNotifier _notifier;

  int? _lastFirst;
  int? _lastLast;

  void _onIndicatorChanged() {
    final paragraphs = _notifier.value?.paragraphs;
    if (paragraphs == null || paragraphs.isEmpty) return;

    // Paragraphs are not guaranteed to be sorted by line index, so scan for the
    // visible band's extremes rather than trusting first/last.
    var first = paragraphs.first.index;
    var last = first;
    for (final paragraph in paragraphs) {
      if (paragraph.index < first) first = paragraph.index;
      if (paragraph.index > last) last = paragraph.index;
    }

    if (first == _lastFirst && last == _lastLast) return;
    _lastFirst = first;
    _lastLast = last;

    unawaited(
      _session.ensureTokensForLines(
        first,
        last,
        awaitResult: false,
        highPriority: true,
      ),
    );
  }

  void dispose() {
    _notifier.removeListener(_onIndicatorChanged);
  }
}
