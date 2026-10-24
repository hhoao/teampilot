import 'dart:collection';

import '../../utils/logging/logger_utils.dart';

/// Which channel a logged frame traveled on.
enum AcpFrameDirection { outgoing, incoming, stderr }

/// Ring-buffered logger for ACP protocol frames.
///
/// Keeps the last [_maxEntries] frames per direction for diagnostics
/// (secrets redacted before storing) and mirrors each entry to [AppLogger]
/// debug output when [mirrorToLog] is true.
///
/// Mirroring is off by default: protocol frames (`session/update`,
/// `available_commands_update`, …) are high-volume and drown out app logs.
/// Turn it on at runtime with the log viewer's ACP toggle (persisted), or
/// compile it in with `--dart-define=ACP_FRAME_LOG=true`.
class AcpFrameLogger {
  /// Compile-time opt-in (`--dart-define=ACP_FRAME_LOG=true`). When true,
  /// mirroring stays on regardless of the persisted toggle (CI / headless).
  static const bool compileTimeEnabled = bool.fromEnvironment('ACP_FRAME_LOG');

  /// Process-wide mirror switch, driven by the persisted user setting (log
  /// viewer toggle) and [compileTimeEnabled]. Read at log time so a toggle
  /// also affects already-running ACP sessions.
  static bool mirrorEnabled = compileTimeEnabled;

  /// Whether mirroring should be on for a persisted [setting].
  static bool resolveEnabled(bool setting) => compileTimeEnabled || setting;

  AcpFrameLogger({bool? mirrorToLog}) : _mirrorOverride = mirrorToLog;

  final bool? _mirrorOverride;

  /// Whether this logger mirrors frames to [AppLogger] (console + disk log).
  /// Defaults to the process-wide [mirrorEnabled]; tests can override.
  bool get mirrorToLog => _mirrorOverride ?? mirrorEnabled;

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
      RegExp(r'"OPENCODE_AUTH_CONTENT"\s*:\s*"(?:\\.|[^"\\])*"');
  static final RegExp _opencodeAuthContentEnvPattern = RegExp(
    r'OPENCODE_AUTH_CONTENT\s*=\s*(?:\{[\s\S]*|\S+)',
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
    if (mirrorToLog) {
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
