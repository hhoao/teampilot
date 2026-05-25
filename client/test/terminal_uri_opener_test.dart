import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_uri_opener.dart';

void main() {
  group('TerminalUriOpener.fixup', () {
    test('trims trailing punctuation from https URL', () {
      expect(
        TerminalUriOpener.fixup('https://example.com).'),
        'https://example.com',
      );
    });

    test('strips localhost from file:// URI', () {
      expect(
        TerminalUriOpener.fixup('file://localhost/tmp/a.txt'),
        'file:///tmp/a.txt',
      );
    });

    test('rejects remote file:// host', () {
      expect(
        TerminalUriOpener.fixup('file://other-host/tmp/a.txt'),
        isNull,
      );
    });
  });
}
