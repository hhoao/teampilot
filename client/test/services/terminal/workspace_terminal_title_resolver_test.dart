import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_title_resolver.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

WorkspaceTerminalEntry _entry(String id, String title) {
  final entry = WorkspaceTerminalEntry(
    id: id,
    cwd: '/tmp',
    spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
    session: _testSession(),
  )..titleLabel = title;
  return entry;
}

void main() {
  group('WorkspaceTerminalTitleResolver', () {
    test('returns base label when unique', () {
      final a = _entry('a', 'Local');
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: a,
          siblings: [a],
          baseLabel: 'Local',
        ),
        'Local',
      );
    });

    test('appends index when siblings share base label', () {
      final a = _entry('a', 'Local');
      final b = _entry('b', 'Local');
      final c = _entry('c', 'user@host');
      final siblings = [a, b, c];
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: a,
          siblings: siblings,
          baseLabel: 'Local',
        ),
        'Local (1)',
      );
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: b,
          siblings: siblings,
          baseLabel: 'Local',
        ),
        'Local (2)',
      );
      expect(
        WorkspaceTerminalTitleResolver.tabTitle(
          entry: c,
          siblings: siblings,
          baseLabel: 'user@host',
        ),
        'user@host',
      );
    });
  });
}
