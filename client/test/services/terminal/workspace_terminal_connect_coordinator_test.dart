import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_connect_coordinator.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

void main() {
  group('WorkspaceTerminalConnectCoordinator.stillLive', () {
    test('true when generation matches and entry remains in group', () {
      final group = WorkspaceTerminalGroup();
      final entry = group.addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final generation = entry.bumpConnectGeneration();
      expect(
        WorkspaceTerminalConnectCoordinator.stillLive(group, entry, generation),
        isTrue,
      );
    });

    test('false after entry removed from group', () {
      final group = WorkspaceTerminalGroup();
      final entry = group.addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final generation = entry.connectGeneration;
      group.removeEntry(entry.id);
      expect(
        WorkspaceTerminalConnectCoordinator.stillLive(group, entry, generation),
        isFalse,
      );
    });

    test('false when generation bumped again', () {
      final group = WorkspaceTerminalGroup();
      final entry = group.addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final generation = entry.bumpConnectGeneration();
      entry.bumpConnectGeneration();
      expect(
        WorkspaceTerminalConnectCoordinator.stillLive(group, entry, generation),
        isFalse,
      );
    });

    test('false after entry disposed', () {
      final group = WorkspaceTerminalGroup();
      final entry = group.addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final generation = entry.connectGeneration;
      entry.dispose();
      expect(
        WorkspaceTerminalConnectCoordinator.stillLive(group, entry, generation),
        isFalse,
      );
    });
  });
}
