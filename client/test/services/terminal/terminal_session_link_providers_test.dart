import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session_link_providers.dart';
import 'package:teampilot/services/terminal/terminal_uri_opener.dart';

void main() {
  group('parseOsc7Cwd', () {
    test('maps a file:// report to a local path', () {
      final expected = TerminalUriOpener.resolveLocalFilePath(
        'file://localhost/tmp/proj',
      );
      expect(
        TerminalSessionLinkProviders.parseOsc7Cwd('file://localhost/tmp/proj'),
        expected,
      );
      expect(expected, isNotNull);
    });

    test('returns null for empty or unparseable reports', () {
      expect(TerminalSessionLinkProviders.parseOsc7Cwd(''), isNull);
      expect(TerminalSessionLinkProviders.parseOsc7Cwd('   '), isNull);
    });
  });
}
