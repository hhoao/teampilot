import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'terminal_session.dart';
import 'workspace_interactive_shell.dart';

const _uuid = Uuid();

/// A single workspace-terminal tab's runtime: its shell session, the view
/// controller (kept alive across widget rebuilds to preserve scroll/selection),
/// its working directory, and whether a connect has been kicked off.
class WorkspaceTerminalEntry {
  WorkspaceTerminalEntry({required this.id, required this.cwd})
    : session = TerminalSession(
        executable: WorkspaceInteractiveShell.executable(),
        validateLaunch: false,
        parseExecutable: false,
      ),
      controller = TerminalController();

  final String id;
  String cwd;
  bool connected = false;
  final TerminalSession session;
  final TerminalController controller;

  String title() {
    final shell = p.basename(WorkspaceInteractiveShell.executable());
    if (cwd.isEmpty) return shell;
    return '$shell ${p.basename(cwd)}';
  }

  void dispose() {
    session.disconnect();
    controller.dispose();
  }
}

/// One workspace's set of workspace-terminal tabs.
class WorkspaceTerminalGroup {
  final List<WorkspaceTerminalEntry> _entries = [];

  /// Id of the selected entry in this group, or null when the group is empty.
  String? activeId;

  List<WorkspaceTerminalEntry> get entries => List.unmodifiable(_entries);

  WorkspaceTerminalEntry? get activeEntry {
    final id = activeId;
    if (id == null) return null;
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  WorkspaceTerminalEntry addEntry({required String cwd, required bool select}) {
    final entry = WorkspaceTerminalEntry(id: _uuid.v4(), cwd: cwd);
    _entries.add(entry);
    if (select) activeId = entry.id;
    return entry;
  }

  /// Removes [id], disposing it, and reselects a neighbour. Returns true when
  /// the group is now empty.
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

/// Owns workspace-terminal groups keyed by `workspaceId`. Lives in DI so terminal
/// sessions survive [WorkspaceTerminalPanel] rebuilds on workspace switch; a
/// group is torn down only when its workspace tab is closed ([disposeWorkspace]).
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
