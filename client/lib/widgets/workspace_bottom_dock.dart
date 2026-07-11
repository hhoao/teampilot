import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/run_cubit.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';
import 'run/run_panel.dart';
import 'workspace_terminal_panel.dart';

/// Which bottom tool is visible in the workspace IDE shell.
enum WorkspaceBottomDockTab { terminal, run }

/// Bottom chrome hosting Terminal and Run with a segmented switcher.
///
/// Preserves [WorkspaceTerminalPanel] identity via [terminalKey] / [holdHandle]
/// so PTY sessions survive dock tab switches and cwd updates.
class WorkspaceBottomDock extends StatefulWidget {
  const WorkspaceBottomDock({
    required this.workspaceId,
    required this.workingDirectory,
    this.holdHandle,
    this.terminalKey,
    this.initialTab = WorkspaceBottomDockTab.terminal,
    super.key,
  });

  final String workspaceId;
  final String workingDirectory;
  final WorkspaceTerminalHoldHandle? holdHandle;
  final Key? terminalKey;
  final WorkspaceBottomDockTab initialTab;

  @override
  State<WorkspaceBottomDock> createState() => _WorkspaceBottomDockState();
}

class _WorkspaceBottomDockState extends State<WorkspaceBottomDock> {
  late WorkspaceBottomDockTab _tab = widget.initialTab;
  Set<String> _seenSessionIds = {};

  void _onSessionsChanged(RunState state) {
    final ids = state.sessions.map((s) => s.id).toSet();
    final added = ids.difference(_seenSessionIds);
    _seenSessionIds = ids;
    if (added.isNotEmpty && _tab != WorkspaceBottomDockTab.run) {
      setState(() => _tab = WorkspaceBottomDockTab.run);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<RunCubit, RunState>(
      listenWhen: (prev, next) => prev.sessions != next.sessions,
      listener: (context, state) => _onSessionsChanged(state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                _DockSegment(
                  label: 'Terminal',
                  selected: _tab == WorkspaceBottomDockTab.terminal,
                  onTap: () => setState(
                    () => _tab = WorkspaceBottomDockTab.terminal,
                  ),
                ),
                const SizedBox(width: 4),
                _DockSegment(
                  label: 'Run',
                  selected: _tab == WorkspaceBottomDockTab.run,
                  onTap: () =>
                      setState(() => _tab = WorkspaceBottomDockTab.run),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab == WorkspaceBottomDockTab.terminal ? 0 : 1,
              children: [
                WorkspaceTerminalPanel(
                  key: widget.terminalKey,
                  workspaceId: widget.workspaceId,
                  workingDirectory: widget.workingDirectory,
                  holdHandle: widget.holdHandle,
                ),
                const RunPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DockSegment extends StatelessWidget {
  const _DockSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: selected
                ? styles.smSemiboldColored(cs.primary)
                : styles.smMediumColored(cs.workspaceMutedText),
          ),
        ),
      ),
    );
  }
}
