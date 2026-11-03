import 'dart:convert';

/// Keeps the last [maxBytes] UTF-8 bytes of a stream of text.
///
/// Command output is unbounded; only the tail is useful for diagnosing a
/// failure, so the head is dropped once the budget is exceeded.
class AutomationTailBuffer {
  AutomationTailBuffer({this.maxBytes = 4096}) : assert(maxBytes > 0);

  static final RegExp _leadingReplacement = RegExp('^\uFFFD+');

  final int maxBytes;
  final StringBuffer _buffer = StringBuffer();
  bool _truncated = false;

  String get text => _buffer.toString();

  bool get truncated => _truncated;

  void add(String chunk) {
    if (chunk.isEmpty) return;
    _buffer.write(chunk);
    _truncateIfNeeded();
  }

  void _truncateIfNeeded() {
    final raw = _buffer.toString();
    final bytes = utf8.encode(raw);
    if (bytes.length <= maxBytes) return;

    _truncated = true;
    final tail = utf8.decode(
      bytes.sublist(bytes.length - maxBytes),
      allowMalformed: true,
    );
    final cleaned = tail.replaceFirst(_leadingReplacement, '');
    _buffer
      ..clear()
      ..write(cleaned);
  }
}
