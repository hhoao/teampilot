import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/workspace_terminal_session_spec.dart';
import 'workspace_shell_connector.dart';
import 'workspace_terminal_connect_coordinator.dart';
import 'workspace_terminal_registry.dart';
import 'workspace_terminal_session_ops.dart';

/// Bind key for Shell Script terminal tab reuse: `(workspaceId, selectionKey)`.
@immutable
class TerminalRunBindKey {
  const TerminalRunBindKey({
    required this.workspaceId,
    required this.selectionKey,
  });

  final String workspaceId;
  final String selectionKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalRunBindKey &&
          workspaceId == other.workspaceId &&
          selectionKey == other.selectionKey;

  @override
  int get hashCode => Object.hash(workspaceId, selectionKey);
}

/// Shared terminal deps for Shell Script Run (wired after connector exists).
@immutable
class TerminalRunDeps {
  const TerminalRunDeps({
    required this.registry,
    required this.connector,
    required this.ops,
    required this.runService,
  });

  final WorkspaceTerminalRegistry registry;
  final WorkspaceShellConnector connector;
  final WorkspaceTerminalSessionOps ops;
  final WorkspaceTerminalRunService runService;
}

/// Lazy holder: [WorkspaceRunRegistry] is created before the shell connector.
class TerminalRunDepsResolver {
  TerminalRunDeps? _deps;

  TerminalRunDeps? get deps => _deps;

  void setDeps(TerminalRunDeps deps) => _deps = deps;

  TerminalRunDeps require() {
    final current = _deps;
    if (current == null) {
      throw StateError('TerminalRunDeps not wired yet');
    }
    return current;
  }
}

/// Opens/reuses workspace Terminal tabs and injects Shell Script commands.
class WorkspaceTerminalRunService {
  WorkspaceTerminalRunService({this.onEntryClosed});

  /// Optional hook for RunSessionManager (tab close → lightweight session exit).
  void Function(String entryId)? onEntryClosed;

  final Map<TerminalRunBindKey, String> _entryByBind = {};
  final Map<String, String> _entryBySession = {};
  final Map<String, TerminalRunBindKey> _bindByEntry = {};

  /// Opens or reuses a terminal entry for a Shell Script run.
  Future<WorkspaceTerminalEntry> openForRun({
    required String workspaceId,
    required String selectionKey,
    required String? runSessionId,
    required bool allowMultipleInstances,
    required String cwd,
    required String targetId,
    required String title,
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required WorkspaceTerminalSessionOps ops,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {
    final bindKey = TerminalRunBindKey(
      workspaceId: workspaceId,
      selectionKey: selectionKey,
    );

    if (!allowMultipleInstances) {
      final existingId = _entryByBind[bindKey];
      if (existingId != null) {
        final existing = group.entryById(existingId);
        if (existing != null) {
          group.activeId = existing.id;
          _bindSessionIfPresent(runSessionId, existing.id);
          // Reconnect if the tab dropped; coordinator no-ops when
          // connected+running.
          await ops.connectEntry(
            group: group,
            entry: existing,
            connectCoordinator: connectCoordinator,
            theme: theme,
            sshConnectFailedMessage: sshConnectFailedMessage,
            onStateChanged: onStateChanged,
            mounted: mounted,
          );
          return existing;
        }
        _clearBind(bindKey, existingId);
      }
    }

    final entry = await ops.openEntry(
      group: group,
      connector: connector,
      connectCoordinator: connectCoordinator,
      cwd: cwd,
      spec: WorkspaceTerminalWorkspaceTargetSpec(targetId),
      theme: theme,
      sshConnectFailedMessage: sshConnectFailedMessage,
      select: true,
      titleLabel: title,
      followWorkspace: false,
      onStateChanged: onStateChanged,
      mounted: mounted,
    );

    _bindEntry(bindKey, entry.id);
    _bindSessionIfPresent(runSessionId, entry.id);
    return entry;
  }

  void registerSessionEntry({
    required String sessionId,
    required String entryId,
  }) {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    _entryBySession[id] = entryId;
  }

  /// Polls [WorkspaceTerminalEntry.session.transportReadyForIo] until ready.
  Future<void> waitForReady(
    WorkspaceTerminalEntry entry, {
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (entry.session.transportReadyForIo) return;
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError(
          'Workspace terminal transport not ready within ${timeout.inSeconds}s',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Writes [line] + `\r` to the PTY when the transport accepts I/O.
  void inject(WorkspaceTerminalEntry entry, String line) {
    entry.session.input.writeToPty('$line\r');
  }

  /// Sends Ctrl+C (`\x03`) to interrupt the running inject.
  void interrupt(WorkspaceTerminalEntry entry) {
    entry.session.input.writeToPty('\x03');
  }

  /// Clears bind maps for a disposed tab; notifies [onEntryClosed] if set.
  void handleEntryClosed(String entryId) {
    final bind = _bindByEntry.remove(entryId);
    if (bind != null && _entryByBind[bind] == entryId) {
      _entryByBind.remove(bind);
    }
    _entryBySession.removeWhere((_, id) => id == entryId);
    onEntryClosed?.call(entryId);
  }

  @visibleForTesting
  String? entryIdForBind({
    required String workspaceId,
    required String selectionKey,
  }) => _entryByBind[TerminalRunBindKey(
    workspaceId: workspaceId,
    selectionKey: selectionKey,
  )];

  @visibleForTesting
  String? entryIdForSession(String sessionId) => _entryBySession[sessionId];

  void _bindEntry(TerminalRunBindKey bindKey, String entryId) {
    final previous = _entryByBind[bindKey];
    if (previous != null && previous != entryId) {
      _bindByEntry.remove(previous);
    }
    _entryByBind[bindKey] = entryId;
    _bindByEntry[entryId] = bindKey;
  }

  void _bindSessionIfPresent(String? runSessionId, String entryId) {
    final id = runSessionId?.trim();
    if (id == null || id.isEmpty) return;
    _entryBySession[id] = entryId;
  }

  void _clearBind(TerminalRunBindKey bindKey, String entryId) {
    if (_entryByBind[bindKey] == entryId) {
      _entryByBind.remove(bindKey);
    }
    _bindByEntry.remove(entryId);
    _entryBySession.removeWhere((_, id) => id == entryId);
  }
}
