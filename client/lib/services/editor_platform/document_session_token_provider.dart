import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

import 'document_session.dart';

/// Adapts a [DocumentSession]'s per-line [TokenSpan]s to re-editor's
/// [CodeTokenProvider].
///
/// Forwards [DocumentSession]'s `notifyListeners` calls (fired whenever new
/// tokens arrive from the tree-sitter worker) so the editor repaints affected
/// lines without owning any tokenization logic itself.
class DocumentSessionTokenProvider extends CodeTokenProvider
    with ChangeNotifier {
  DocumentSessionTokenProvider(this._session) {
    _session.addListener(_forward);
  }

  final DocumentSession _session;

  void _forward() => notifyListeners();

  @override
  List<CodeTokenSpan> tokensForLine(int lineIndex) {
    final spans = _session.tokensForLine(lineIndex);
    if (spans.isEmpty) return const <CodeTokenSpan>[];
    return spans
        .map(
          (span) => CodeTokenSpan(
            start: span.start,
            length: span.length,
            scope: span.scope,
          ),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _session.removeListener(_forward);
    super.dispose();
  }
}
