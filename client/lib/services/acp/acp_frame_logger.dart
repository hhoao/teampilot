import 'dart:collection';

import '../../utils/logging/logger_utils.dart';

/// Which channel a logged frame traveled on.
enum AcpFrameDirection { outgoing, incoming, stderr }

/// Ring-buffered logger for ACP protocol frames.
///
/// Keeps the last [_maxEntries] frames per direction for diagnostics
/// (secrets redacted before storing) and mirrors each entry to [AppLogger]
/// debug output when [enableDiskLog] is true.
class AcpFrameLogger {
  AcpFrameLogger({this.enableDiskLog = true});

  /// Whether frames are mirrored to [AppLogger] (disk/console log).
  final bool enableDiskLog;

  static const int _maxEntries = 200;

  /// JSON-RPC frames carry the key quoted (`"GEMINI_API_KEY": "…"`); agent
  /// stderr lines carry the env form (`GEMINI_API_KEY=…`). Both must be
  /// redacted before anything is buffered or mirrored to disk.
  static final RegExp _geminiApiKeyQuotedPattern =
      RegExp(r'"GEMINI_API_KEY"\s*:\s*"[^"]*"');
  static final RegExp _geminiApiKeyEnvPattern = RegExp(
    r'GEMINI_API_KEY\s*=\s*\S+',
  );
  static final RegExp _cursorApiKeyQuotedPattern =
      RegExp(r'"CURSOR_API_KEY"\s*:\s*"[^"]*"');
  static final RegExp _cursorApiKeyEnvPattern = RegExp(
    r'CURSOR_API_KEY\s*=\s*\S+',
  );
  static final RegExp _cursorAuthTokenQuotedPattern =
      RegExp(r'"CURSOR_AUTH_TOKEN"\s*:\s*"[^"]*"');
  static final RegExp _cursorAuthTokenEnvPattern = RegExp(
    r'CURSOR_AUTH_TOKEN\s*=\s*\S+',
  );
  static final RegExp _opencodeAuthContentQuotedPattern =
      RegExp(r'"OPENCODE_AUTH_CONTENT"\s*:\s*"[^"]*"');
  static final RegExp _opencodeAuthContentEnvPattern = RegExp(
    r'OPENCODE_AUTH_CONTENT\s*=\s*\S+',
  );

  final ListQueue<String> _outgoing = ListQueue<String>();
  final ListQueue<String> _incoming = ListQueue<String>();
  final ListQueue<String> _stderr = ListQueue<String>();

  /// Logs a frame (JSON-RPC message) sent to the agent.
  void logOutgoing(String frame) =>
      _record(_outgoing, 'ACP →', _redact(frame));

  /// Logs a frame (JSON-RPC message) received from the agent.
  void logIncoming(String frame) =>
      _record(_incoming, 'ACP ←', _redact(frame));

  /// Logs one stderr line from the agent.
  void logStderr(String line) => _record(_stderr, 'ACP !', _redact(line));

  /// Returns buffered entries, oldest first.
  ///
  /// Without [direction], entries from all channels are combined
  /// (insertion order per channel is preserved but channels interleave).
  List<String> snapshot({AcpFrameDirection? direction}) {
    switch (direction) {
      case AcpFrameDirection.outgoing:
        return List<String>.of(_outgoing);
      case AcpFrameDirection.incoming:
        return List<String>.of(_incoming);
      case AcpFrameDirection.stderr:
        return List<String>.of(_stderr);
      case null:
        return [
          ...List<String>.of(_outgoing),
          ...List<String>.of(_incoming),
          ...List<String>.of(_stderr),
        ];
    }
  }

  void _record(ListQueue<String> buffer, String tag, String text) {
    buffer.addLast(text);
    while (buffer.length > _maxEntries) {
      buffer.removeFirst();
    }
    if (enableDiskLog) {
      AppLogger.instance.d('[$tag] $text');
    }
  }

  static String _redact(String text) {
    var redacted = text.replaceAll(
      _geminiApiKeyQuotedPattern,
      '"GEMINI_API_KEY": "[REDACTED]"',
    );
    redacted = redacted.replaceAll(
      _geminiApiKeyEnvPattern,
      'GEMINI_API_KEY=[REDACTED]',
    );
    redacted = redacted.replaceAll(
      _cursorApiKeyQuotedPattern,
      '"CURSOR_API_KEY": "[REDACTED]"',
    );
    redacted = redacted.replaceAll(
      _cursorApiKeyEnvPattern,
      'CURSOR_API_KEY=[REDACTED]',
    );
    redacted = redacted.replaceAll(
      _cursorAuthTokenQuotedPattern,
      '"CURSOR_AUTH_TOKEN": "[REDACTED]"',
    );
    redacted = redacted.replaceAll(
      _cursorAuthTokenEnvPattern,
      'CURSOR_AUTH_TOKEN=[REDACTED]',
    );
    redacted = redacted.replaceAll(
      _opencodeAuthContentQuotedPattern,
      '"OPENCODE_AUTH_CONTENT": "[REDACTED]"',
    );
    redacted = redacted.replaceAll(
      _opencodeAuthContentEnvPattern,
      'OPENCODE_AUTH_CONTENT=[REDACTED]',
    );
    return redacted;
  }
}
