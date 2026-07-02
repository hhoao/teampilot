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
}
