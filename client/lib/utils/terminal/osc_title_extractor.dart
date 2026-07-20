/// OSC title extraction from raw PTY output (cmds 0/1/2).
///
/// Ported from Orca `osc-title-extraction.ts` + scan-tail for chunked feeds.
class OscTitleExtractor {
  static const int maxOscTitleChars = 1024;
  static const int _scanTailLimit = 4096;
  static const int _oscPrefixLength = 4;

  static const int _esc = 0x1b;
  static const int _bel = 0x07;
  static const int _rightBracket = 0x5d;
  static const int _backslash = 0x5c;
  static const int _semicolon = 0x3b;
  static const Set<int> _titleCommands = {0x30, 0x31, 0x32}; // '0','1','2'

  String _pending = '';

  /// Feed a PTY text chunk; returns newly completed titles in order.
  List<String> push(String data) {
    if (data.isEmpty && _pending.isEmpty) return const [];
    final input = '$_pending$data';
    final titles = extractAll(input);
    _pending = _scanTail(input);
    return titles;
  }

  void reset() => _pending = '';

  /// Last complete OSC title in [data], or null.
  static String? extractLast(String data) {
    if (!data.contains('\x1b]')) return null;
    String? last;
    var searchStart = 0;
    while (searchStart < data.length) {
      final start = data.indexOf('\x1b]', searchStart);
      if (start == -1) break;
      final parsed = _parseAt(data, start);
      switch (parsed) {
        case _OscTitleResultTitle(:final title, :final nextIndex):
          last = title;
          searchStart = nextIndex;
        case _OscTitleResultInvalid(:final nextIndex):
          searchStart = nextIndex;
        case _OscTitleResultIncomplete():
          return last;
      }
    }
    return last;
  }

  /// All complete OSC titles in [data] (cmds 0/1/2).
  static List<String> extractAll(String data) {
    if (!data.contains('\x1b]')) return const [];
    final titles = <String>[];
    var searchStart = 0;
    while (searchStart < data.length) {
      final start = data.indexOf('\x1b]', searchStart);
      if (start == -1) break;
      final parsed = _parseAt(data, start);
      switch (parsed) {
        case _OscTitleResultTitle(:final title, :final nextIndex):
          titles.add(title);
          searchStart = nextIndex;
        case _OscTitleResultInvalid(:final nextIndex):
          searchStart = nextIndex;
        case _OscTitleResultIncomplete():
          return titles;
      }
    }
    return titles;
  }

  static String _scanTail(String input) {
    final lastOsc = input.lastIndexOf('\x1b]');
    if (lastOsc != -1) {
      final suffix = input.substring(lastOsc);
      if (!suffix.contains('\x07') && !suffix.contains('\x1b\\')) {
        return _trimScanTail(suffix);
      }
      return input.endsWith('\x1b') ? '\x1b' : '';
    }
    return input.endsWith('\x1b') ? '\x1b' : '';
  }

  static String _trimScanTail(String value) {
    if (value.length <= _scanTailLimit) return value;
    final prefixLen = value.length < _oscPrefixLength
        ? value.length
        : _oscPrefixLength;
    final prefix = value.substring(0, prefixLen);
    final suffixBudget = _scanTailLimit - prefix.length;
    if (suffixBudget <= 0) return prefix;
    return '$prefix${value.substring(value.length - suffixBudget)}';
  }

  static _OscTitleParseResult _parseAt(String data, int index) {
    if (!_isIntroducerAt(data, index)) {
      return _OscTitleResultInvalid(index + 1);
    }
    if (index + 3 >= data.length) {
      return const _OscTitleResultIncomplete();
    }
    if (!_titleCommands.contains(data.codeUnitAt(index + 2)) ||
        data.codeUnitAt(index + 3) != _semicolon) {
      return _OscTitleResultInvalid(index + 2);
    }

    final titleStart = index + 4;
    for (var cursor = titleStart; cursor < data.length; cursor++) {
      final code = data.codeUnitAt(cursor);
      if (code == _bel) {
        return _OscTitleResultTitle(
          title: _boundedTitle(data, titleStart, cursor),
          nextIndex: cursor + 1,
        );
      }
      if (code != _esc) continue;
      if (cursor + 1 >= data.length) {
        return const _OscTitleResultIncomplete();
      }
      if (data.codeUnitAt(cursor + 1) == _backslash) {
        return _OscTitleResultTitle(
          title: _boundedTitle(data, titleStart, cursor),
          nextIndex: cursor + 2,
        );
      }
      return _OscTitleResultInvalid(cursor);
    }
    return const _OscTitleResultIncomplete();
  }

  static bool _isIntroducerAt(String data, int index) =>
      index + 1 < data.length &&
      data.codeUnitAt(index) == _esc &&
      data.codeUnitAt(index + 1) == _rightBracket;

  static String _boundedTitle(String data, int titleStart, int titleEnd) {
    final length = titleEnd - titleStart;
    if (length <= maxOscTitleChars) {
      return data.substring(titleStart, titleEnd);
    }
    final prefixLength = (maxOscTitleChars / 2).ceil();
    final suffixLength = maxOscTitleChars - prefixLength;
    return data.substring(titleStart, titleStart + prefixLength) +
        data.substring(titleEnd - suffixLength, titleEnd);
  }
}

sealed class _OscTitleParseResult {
  const _OscTitleParseResult();
}

final class _OscTitleResultTitle extends _OscTitleParseResult {
  const _OscTitleResultTitle({required this.title, required this.nextIndex});
  final String title;
  final int nextIndex;
}

final class _OscTitleResultInvalid extends _OscTitleParseResult {
  const _OscTitleResultInvalid(this.nextIndex);
  final int nextIndex;
}

final class _OscTitleResultIncomplete extends _OscTitleParseResult {
  const _OscTitleResultIncomplete();
}
