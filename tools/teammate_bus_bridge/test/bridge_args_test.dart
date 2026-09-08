import 'package:test/test.dart';

import '../bin/teammate_bus_bridge.dart';

void main() {
  group('parseBridgeArgs', () {
    test('parses --session alongside member and bus-url', () {
      expect(
        parseBridgeArgs([
          '--member',
          'alice',
          '--session',
          'sess-1',
          '--bus-url',
          'http://127.0.0.1:9/mcp',
        ]),
        {
          'member': 'alice',
          'session': 'sess-1',
          'bus-url': 'http://127.0.0.1:9/mcp',
        },
      );
    });

    test('parses --session=value form', () {
      expect(
        parseBridgeArgs(['--session=sess-2', '--member=bob']),
        {'session': 'sess-2', 'member': 'bob'},
      );
    });
  });

  group('parseExtraHeaders', () {
    test('parses --extra-header Name:Value pairs', () {
      expect(
        parseExtraHeaders([
          '--extra-header',
          'X-Team-Generation-Token:tok-1',
        ]),
        [('X-Team-Generation-Token', 'tok-1')],
      );
    });

    test('keeps repeated headers in order', () {
      expect(
        parseExtraHeaders([
          '--extra-header',
          'X-Team-Generation-Token:tok-1',
          '--extra-header',
          'X-Other:v',
        ]),
        [('X-Team-Generation-Token', 'tok-1'), ('X-Other', 'v')],
      );
    });

    test('supports --extra-header=Name:Value form', () {
      expect(
        parseExtraHeaders(['--extra-header=X-A:1']),
        [('X-A', '1')],
      );
    });

    test('skips malformed entries without a colon', () {
      expect(parseExtraHeaders(['--extra-header', 'no-colon']), isEmpty);
    });

    test('ignores other flags and their values', () {
      expect(
        parseExtraHeaders([
          '--member',
          'alice',
          '--extra-header',
          'X-Team-Generation-Token:tok-1',
        ]),
        [('X-Team-Generation-Token', 'tok-1')],
      );
    });
  });
}
