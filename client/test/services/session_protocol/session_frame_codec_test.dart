import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_protocol/session_envelope.dart';
import 'package:teampilot/services/session_protocol/session_frame_codec.dart';

void main() {
  test('encodes and decodes one frame', () {
    final frame = encodeSessionFrame(
      const SessionEnvelope(
        type: SessionMessageType.hello,
        channel: SessionChannel.control,
        body: {'proto': 1},
      ),
    );
    final decoder = SessionFrameDecoder();

    final decoded = decoder.add(frame);

    expect(decoded, hasLength(1));
    expect(decoded.single.type, SessionMessageType.hello);
    expect(decoded.single.body['proto'], 1);
  });

  test('handles partial reads and coalesced frames', () {
    final first = encodeSessionFrame(
      const SessionEnvelope(
        type: SessionMessageType.ping,
        channel: SessionChannel.control,
      ),
    );
    final second = encodeSessionFrame(
      const SessionEnvelope(
        type: SessionMessageType.pong,
        channel: SessionChannel.control,
      ),
    );
    final decoder = SessionFrameDecoder();

    expect(decoder.add(first.sublist(0, 2)), isEmpty);
    expect(decoder.add(first.sublist(2)), hasLength(1));
    expect(
      decoder.add([...second.sublist(0, 1), ...second.sublist(1)]),
      hasLength(1),
    );
  });

  test('marks the stream broken for an oversize length prefix', () {
    final prefix = Uint8List(4);
    ByteData.sublistView(
      prefix,
    ).setUint32(0, sessionMaxFrameBytes + 1, Endian.big);
    final decoder = SessionFrameDecoder();

    expect(decoder.add(prefix), isEmpty);
    expect(decoder.isBroken, isTrue);
  });

  test('skips invalid JSON and keeps decoding', () {
    final badPayload = utf8.encode('{not json');
    final bad = Uint8List(4 + badPayload.length);
    ByteData.sublistView(bad).setUint32(0, badPayload.length, Endian.big);
    bad.setRange(4, bad.length, badPayload);
    final good = encodeSessionFrame(
      const SessionEnvelope(
        type: SessionMessageType.ping,
        channel: SessionChannel.control,
      ),
    );
    final decoder = SessionFrameDecoder();

    final decoded = decoder.add([...bad, ...good]);

    expect(decoded, hasLength(1));
    expect(decoded.single.type, SessionMessageType.ping);
    expect(decoder.isBroken, isFalse);
  });
}
