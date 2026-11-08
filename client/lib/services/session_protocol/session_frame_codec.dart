import 'dart:convert';
import 'dart:typed_data';

import 'session_envelope.dart';

/// Hard cap for one frame (including the 4-byte length prefix? no, payload).
const sessionMaxFrameBytes = 1024 * 1024;

/// `u32 big-endian length | UTF-8 JSON envelope`.
List<int> encodeSessionFrame(SessionEnvelope envelope) {
  final payload = utf8.encode(jsonEncode(envelope.toJson()));
  if (payload.length > sessionMaxFrameBytes) {
    throw StateError('session frame too large: ${payload.length}');
  }
  final frame = Uint8List(4 + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);
  frame.setRange(4, frame.length, payload);
  return frame;
}

/// Incremental frame decoder. Handles partial reads and coalesced frames;
/// invalid JSON is skipped, an invalid length marks the stream broken.
final class SessionFrameDecoder {
  final List<int> _buffer = <int>[];
  bool _broken = false;

  bool get isBroken => _broken;

  int get bufferedBytes => _buffer.length;

  List<SessionEnvelope> add(List<int> chunk) {
    if (_broken || chunk.isEmpty) return const [];
    _buffer.addAll(chunk);
    final frames = <SessionEnvelope>[];
    while (_buffer.length >= 4) {
      final length = ByteData.sublistView(
        Uint8List.fromList(_buffer.sublist(0, 4)),
      ).getUint32(0, Endian.big);
      if (length > sessionMaxFrameBytes) {
        _broken = true;
        _buffer.clear();
        return frames;
      }
      if (_buffer.length < 4 + length) break;
      final payload = Uint8List.fromList(_buffer.sublist(4, 4 + length));
      _buffer.removeRange(0, 4 + length);
      try {
        final envelope = SessionEnvelope.fromJson(
          jsonDecode(utf8.decode(payload)),
        );
        if (envelope != null) frames.add(envelope);
      } on FormatException {
        // A truncated/garbled payload is dropped; the stream stays usable.
      }
    }
    return frames;
  }

  void reset() {
    _buffer.clear();
    _broken = false;
  }
}
