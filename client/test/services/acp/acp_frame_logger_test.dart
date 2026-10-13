import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';

void main() {
  test('redacts GEMINI_API_KEY values in frames', () {
    final logger = AcpFrameLogger();
    logger.logOutgoing(
      jsonEncode({
        'method': 'session/prompt',
        'env': {'GEMINI_API_KEY': 'super-secret'},
      }),
    );
    final text = logger.snapshot().join('\n');
    expect(text, contains('[REDACTED]'));
    expect(text, isNot(contains('super-secret')));
  });

  test('ring buffer caps at 200 entries, oldest dropped', () {
    final logger = AcpFrameLogger();
    for (var i = 0; i < 250; i++) {
      logger.logIncoming('frame-$i');
    }
    final all = logger.snapshot();
    expect(all.length, 200);
    expect(all.first, 'frame-50');
    expect(all.last, 'frame-249');
  });

  test('ring buffers are independent per direction', () {
    final logger = AcpFrameLogger();
    logger.logOutgoing('out-1');
    logger.logIncoming('in-1');
    logger.logIncoming('in-2');
    logger.logStderr('err-1');
    expect(logger.snapshot(direction: AcpFrameDirection.outgoing), ['out-1']);
    expect(
      logger.snapshot(direction: AcpFrameDirection.incoming),
      ['in-1', 'in-2'],
    );
    expect(logger.snapshot(direction: AcpFrameDirection.stderr), ['err-1']);
  });

  test('snapshot without direction returns all buffered entries', () {
    final logger = AcpFrameLogger();
    logger.logOutgoing('out-1');
    logger.logIncoming('in-1');
    logger.logStderr('err-1');
    final all = logger.snapshot();
    expect(all.length, 3);
    expect(all.toSet(), {'out-1', 'in-1', 'err-1'});
  });

  test('redacts GEMINI_API_KEY in stderr env form too', () {
    final logger = AcpFrameLogger();
    logger.logStderr('GEMINI_API_KEY=super-secret-2');
    final text = logger.snapshot().join('\n');
    expect(text, isNot(contains('super-secret-2')));
    expect(text, contains('GEMINI_API_KEY=[REDACTED]'));
  });

  test('redacts CURSOR_API_KEY values in frames', () {
    final logger = AcpFrameLogger();
    logger.logOutgoing(
      jsonEncode({
        'method': 'session/prompt',
        'env': {'CURSOR_API_KEY': 'secret'},
      }),
    );
    final text = logger.snapshot().join('\n');
    expect(text, contains('[REDACTED]'));
    expect(text, isNot(contains('secret')));
  });

  test('redacts CURSOR_AUTH_TOKEN in stderr env form too', () {
    final logger = AcpFrameLogger();
    logger.logStderr('CURSOR_AUTH_TOKEN=secret');
    final text = logger.snapshot().join('\n');
    expect(text, isNot(contains('secret')));
    expect(text, contains('CURSOR_AUTH_TOKEN=[REDACTED]'));
  });

  test('redacts OPENCODE_AUTH_CONTENT values in frames', () {
    final logger = AcpFrameLogger();
    logger.logOutgoing(
      jsonEncode({
        'method': 'session/prompt',
        'env': {'OPENCODE_AUTH_CONTENT': 'super-secret'},
      }),
    );
    final text = logger.snapshot().join('\n');
    expect(text, contains('[REDACTED]'));
    expect(text, isNot(contains('super-secret')));
  });

  test('redacts OPENCODE_AUTH_CONTENT in stderr env form too', () {
    final logger = AcpFrameLogger();
    logger.logStderr('OPENCODE_AUTH_CONTENT=super-secret-2');
    final text = logger.snapshot().join('\n');
    expect(text, isNot(contains('super-secret-2')));
    expect(text, contains('OPENCODE_AUTH_CONTENT=[REDACTED]'));
  });

  test('can disable disk log mirroring', () {
    final logger = AcpFrameLogger(enableDiskLog: false);
    logger.logOutgoing('{"ok":true}');
    expect(logger.snapshot(), isNotEmpty);
  });
}
