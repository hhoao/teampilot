import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Byte-pipe abstraction over an ACP agent process.
///
/// Implementations deliver raw NDJSON bytes via [input], accept
/// newline-terminated JSON-RPC frames via [write], and keep the agent's
/// stderr fully separate from the protocol channel.
abstract class AcpTransport {
  /// Raw stdout of the agent process (NDJSON bytes, no PTY).
  Stream<Uint8List> get input;

  /// Writes one JSON-RPC frame as a single newline-terminated line.
  void write(String frame);

  /// Agent stderr, kept separate from [input] (never merged).
  Stream<List<int>> get stderr;

  /// Gracefully terminates the agent (SIGTERM → timeout → SIGKILL).
  Future<void> close();

  /// Whether [close] has been requested.
  bool get isClosed;
}

/// Splits an NDJSON byte stream into individual frame strings.
///
/// Buffers partial frames across chunk boundaries. The byte stream is run
/// through the stateful [Utf8Decoder] transformer first, so multi-byte UTF-8
/// sequences split across chunk boundaries are carried over instead of being
/// corrupted with U+FFFD replacement characters.
class NdjsonDecoder {
  /// Decodes [bytes] into a stream of complete NDJSON frame strings.
  ///
  /// A trailing frame without a final `\n` is emitted when the stream ends.
  /// Empty lines are skipped.
  Stream<String> decode(Stream<Uint8List> bytes) async* {
    final buffer = StringBuffer();
    await for (final chunk in bytes
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))) {
      buffer.write(chunk);
      var content = buffer.toString();
      var newline = content.indexOf('\n');
      while (newline >= 0) {
        var line = content.substring(0, newline);
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        if (line.isNotEmpty) {
          yield line;
        }
        content = content.substring(newline + 1);
        newline = content.indexOf('\n');
      }
      buffer
        ..clear()
        ..write(content);
    }
    final tail = buffer.toString();
    if (tail.isNotEmpty) {
      yield tail;
    }
  }
}
