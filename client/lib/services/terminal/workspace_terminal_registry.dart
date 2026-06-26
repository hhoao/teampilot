import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:uuid/uuid.dart';

import '../../models/workspace_terminal_session_spec.dart';
import 'terminal_session.dart';
import 'workspace_shell_connector.dart';

const _uuid = Uuid();

/// A single workspace-terminal tab: spec, cwd, session, and view controller.
class WorkspaceTerminalEntry {
  WorkspaceTerminalEntry({
    required this.id,
    required this.cwd,
    required this.spec,
    required this.session,
    this.followWorkspace = false,
  }) : controller = TerminalController();

  final String id;
  String cwd;
  WorkspaceTerminalSessionSpec spec;
  TerminalSession session;

  /// When true, cwd changes re-resolve [spec] via [defaultSessionSpecFor].
  bool followWorkspace;

  bool connected = false;
  int connectGeneration = 0;
  final TerminalController controller;

  /// Cached display label from [WorkspaceShellConnector.labelForSpec].
  String titleLabel = '';

  int bumpConnectGeneration() => ++connectGeneration;

  void dispose() {
    bumpConnectGeneration();
    session.sshMemberSession?.close();
    session.disconnect();
    session.dispose();
    controller.dispose();
  }
}

/// One workspace's IDEA-style terminal tabs.
class WorkspaceTerminalGroup {
  final List<WorkspaceTerminalEntry> _entries = [];

  String? activeId;

  List<WorkspaceTerminalEntry> get entries => List.unmodifiable(_entries);

  bool contains(String id) => _entries.any((e) => e.id == id);

  WorkspaceTerminalEntry? entryById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  WorkspaceTerminalEntry? get activeEntry {
    final id = activeId;
    if (id == null) return null;
    return entryById(id);
  }

  WorkspaceTerminalEntry addEntry({
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalSession session,
    required bool select,
    String titleLabel = '',
    bool followWorkspace = false,
  }) {
    final entry = WorkspaceTerminalEntry(
      id: _uuid.v4(),
      cwd: cwd,
      spec: spec,
      session: session,
      followWorkspace: followWorkspace,
    )..titleLabel = titleLabel;
    _entries.add(entry);
    if (select) activeId = entry.id;
    return entry;
  }

  bool removeEntry(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return _entries.isEmpty;
    final wasActive = _entries[index].id == activeId;
    _entries[index].dispose();
    _entries.removeAt(index);
    if (_entries.isEmpty) {
      activeId = null;
      return true;
    }
    if (wasActive) {
      final next = index >= _entries.length ? _entries.length - 1 : index;
      activeId = _entries[next].id;
    }
    return false;
  }

  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    _entries.clear();
    activeId = null;
  }
}

/// Owns workspace-terminal groups keyed by workspace tab id.
class WorkspaceTerminalRegistry {
  final Map<String, WorkspaceTerminalGroup> _groups = {};

  WorkspaceTerminalGroup groupFor(String workspaceId) =>
      _groups.putIfAbsent(workspaceId, WorkspaceTerminalGroup.new);

  void disposeWorkspace(String workspaceId) {
    _groups.remove(workspaceId)?.dispose();
  }

  void disposeAll() {
    for (final g in _groups.values) {
      g.dispose();
    }
    _groups.clear();
  }
}
