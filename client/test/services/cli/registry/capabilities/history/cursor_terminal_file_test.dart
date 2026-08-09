import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/terminal_file.dart';

void main() {
  group('parseCursorTerminalFile', () {
    test('parses full header, body, and exit trailer', () {
      const raw = '''
---
pid: 12345
cwd: "/home/user/proj"
command: "git status"
title: "git status"
status: succeeded
started_at: 2026-07-29T10:00:00.000Z
running_for_ms: 42
---
On branch main
nothing to commit
---
exit_code: 0
elapsed_ms: 150
ended_at: 2026-07-29T10:00:00.150Z
---
''';

      final parsed = parseCursorTerminalFile(raw);

      expect(parsed, isNotNull);
      expect(parsed!.pid, '12345');
      expect(parsed.cwd, '/home/user/proj');
      expect(parsed.command, 'git status');
      expect(parsed.title, 'git status');
      expect(parsed.status, 'succeeded');
      expect(parsed.startedAt, '2026-07-29T10:00:00.000Z');
      expect(parsed.runningForMs, 42);
      expect(parsed.body, 'On branch main\nnothing to commit');
      expect(parsed.exitCode, 0);
      expect(parsed.elapsedMs, 150);
      expect(parsed.endedAt, '2026-07-29T10:00:00.150Z');
    });

    test('returns body when exit trailer is missing', () {
      const raw = '''
---
pid: 99
command: "echo hi"
title: "echo hi"
status: failed
started_at: 2026-07-29T11:00:00.000Z
---
hello from terminal
''';

      final parsed = parseCursorTerminalFile(raw);

      expect(parsed, isNotNull);
      expect(parsed!.command, 'echo hi');
      expect(parsed.body, 'hello from terminal');
      expect(parsed.exitCode, isNull);
      expect(parsed.elapsedMs, isNull);
      expect(parsed.endedAt, isNull);
    });

    test('parses CRLF fence lines from Windows terminal files', () {
      const raw =
          '---\r\n'
          'pid: 12345\r\n'
          'command: "pwd"\r\n'
          'title: "pwd"\r\n'
          'status: succeeded\r\n'
          'started_at: 2026-07-29T10:00:00.000Z\r\n'
          '---\r\n'
          '/home/hhoa/proj\r\n'
          '---\r\n'
          'exit_code: 0\r\n'
          'elapsed_ms: 50\r\n'
          'ended_at: 2026-07-29T10:00:00.050Z\r\n'
          '---\r\n';

      final parsed = parseCursorTerminalFile(raw);

      expect(parsed, isNotNull);
      expect(parsed!.command, 'pwd');
      expect(parsed.body, '/home/hhoa/proj');
      expect(parsed.exitCode, 0);
    });

    test('returns null for garbage input', () {
      expect(parseCursorTerminalFile('not a terminal file'), isNull);
      expect(parseCursorTerminalFile('---\nno command here\n---\nbody\n'), isNull);
      expect(parseCursorTerminalFile('---\ncommand: ""\n---\nbody\n'), isNull);
      expect(parseCursorTerminalFile('---\ncommand: "   "\n---\nbody\n'), isNull);
    });
  });
}
