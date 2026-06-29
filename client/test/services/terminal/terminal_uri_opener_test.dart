import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

    test('wraps bare absolute POSIX path as file URI', () {
      if (Platform.isWindows) return;
      expect(
        TerminalUriOpener.fixup('/home/hhoa/.claude/CLAUDE.md'),
        'file:///home/hhoa/.claude/CLAUDE.md',
      );
    });

    test('leaves https URLs unchanged', () {
      expect(
        TerminalUriOpener.fixup('https://example.com'),
        'https://example.com',
      );
    });

    test('strips :line suffix before resolving bare file paths', () {
      if (Platform.isWindows) return;
      expect(
        TerminalUriOpener.fixup(
          'client/lib/pages/chat/chat_scoped_tab_view.dart:1',
        ),
        'file:/client/lib/pages/chat/chat_scoped_tab_view.dart',
      );
    });

    test('strips :line:col suffix before resolving bare file paths', () {
      if (Platform.isWindows) return;
      expect(
        TerminalUriOpener.fixup('src/main.dart:42:7'),
        'file:/src/main.dart',
      );
    });
  });

  group('TerminalUriOpener.resolveLocalFilePath', () {
    test('returns absolute path for file URI', () {
      final expected = Platform.isWindows ? r'\tmp\a.txt' : '/tmp/a.txt';
      expect(
        TerminalUriOpener.resolveLocalFilePath('file:///tmp/a.txt'),
        expected,
      );
    });

    test('joins relative file path with working directory', () {
      final wd = Platform.isWindows ? r'C:\workspace' : '/workspace';
      expect(
        TerminalUriOpener.resolveLocalFilePath(
          'file:/src/main.dart',
          workingDirectory: wd,
        ),
        p.normalize(p.join(wd, 'src', 'main.dart')),
      );
    });

    test('resolves bare absolute path without file prefix', () {
      if (Platform.isWindows) return;
      expect(
        TerminalUriOpener.resolveLocalFilePath('/home/hhoa/.claude/CLAUDE.md'),
        '/home/hhoa/.claude/CLAUDE.md',
      );
    });

    test('resolves bare relative path with working directory', () {
      if (Platform.isWindows) return;
      expect(
        TerminalUriOpener.resolveLocalFilePath(
          'src/main.dart',
          workingDirectory: '/workspace',
        ),
        '/workspace/src/main.dart',
      );
    });

    test('resolves relative path with :line suffix', () {
      if (Platform.isWindows) return;
      expect(
        TerminalUriOpener.resolveLocalFilePath(
          'client/lib/foo.dart:1',
          workingDirectory: '/workspace',
        ),
        '/workspace/client/lib/foo.dart',
      );
    });
  });
}
