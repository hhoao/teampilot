import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/run_session.dart';
import '../../widgets/run/run_session_dismiss.dart';
import '../terminal/workspace_terminal_registry.dart';
import '../terminal/workspace_terminal_run_service.dart';

/// Whether selecting a workbench tab should also sync [ChatCubit.selectTab].
@visibleForTesting
bool workbenchSelectSyncsChatTab(WorkbenchTabKind kind) =>
    kind == WorkbenchTabKind.session;

/// Whether [WorkbenchShellActions.closeAt] should remove a run strip tab after
/// attempting domain dismiss.
///
/// Orphaned tabs (session already gone) always drop from the strip. When the
/// session still exists, remove only if confirm/dismiss succeeded — cancel
/// must leave both domain and strip intact.
@visibleForTesting
bool shouldRemoveRunWorkbenchTab({
  required bool sessionFound,
  required bool dismissSucceeded,
}) => !sessionFound || dismissSucceeded;

/// Clears run-service binds then removes the shell entry from its group.
void disposeWorkbenchShellDomain({
  required WorkspaceTerminalRunService runService,
  required WorkspaceTerminalGroup group,
  required String entryId,
}) {
  runService.handleEntryClosed(entryId);
  group.removeEntry(entryId);
}

/// Tab-bar actions for the unified workbench (session / file / diff / shell / run).
abstract final class WorkbenchShellActions {
  WorkbenchShellActions._();

  static Future<void> select({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId tab,
  }) async {
    selectResolved(
      workbench: context.read<WorkbenchCubit>(),
      chat: context.read<ChatCubit>(),
      workspaceId: workspaceId,
      tabScopeId: tabScopeId,
      tab: tab,
    );
  }

  /// Context-free select used by keyboard strip navigation and the tab bar.
  ///
  /// The bar's active is the single source; the bridge mirrors it into
  /// [ChatState]. No chat-side tab selection is performed here anymore.
  static void selectResolved({
    required WorkbenchCubit workbench,
    required ChatCubit chat,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId tab,
  }) {
    workbench.activate(workspaceId, tab);
  }

  static Future<void> closeAt({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId tab,
  }) async {
    final workbench = context.read<WorkbenchCubit>();
    final editor = context.read<EditorCubit>();

    switch (tab.kind) {
      case WorkbenchTabKind.file:
        final dirty = editor.state.bucket(workspaceId).isDirty(tab.id);
        if (dirty) {
          final discard = await _confirmDiscard(context);
          if (discard != true || !context.mounted) return;
        }
        editor.closeFile(workspaceId, tab.id, force: true);
      case WorkbenchTabKind.diff:
        editor.closeDiff(workspaceId, tab.id);
      case WorkbenchTabKind.shell:
        disposeWorkbenchShellDomain(
          runService: context.read<WorkspaceTerminalRunService>(),
          group: context.read<WorkspaceTerminalRegistry>().groupFor(tabScopeId),
          entryId: tab.id,
        );
      case WorkbenchTabKind.run:
        final runCubit = context.read<RunCubit>();
        final session = _runSessionById(runCubit.state.sessions, tab.id);
        if (session != null) {
          final dismissed = await dismissRunSessionWithConfirm(
            context: context,
            cubit: runCubit,
            session: session,
          );
          if (!shouldRemoveRunWorkbenchTab(
                sessionFound: true,
                dismissSucceeded: dismissed,
              ) ||
              !context.mounted) {
            return;
          }
        }
      case WorkbenchTabKind.session:
        // Teardown handled by the port (chat.teardownSession) after the bar
        // removes the entry via [WorkbenchCubit.close].
        break;
    }
    await workbench.close(workspaceId, tab);
  }

  static Future<void> closeOthers({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId keep,
  }) async {
    final workbench = context.read<WorkbenchCubit>();
    final removed = workbench.closeOthers(workspaceId, keep);
    for (final tab in removed) {
      if (!context.mounted) return;
      await _closeDomainOnly(
        context: context,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        tab: tab,
      );
    }
    if (!context.mounted) return;
    await select(
      context: context,
      workspaceId: workspaceId,
      tabScopeId: tabScopeId,
      tab: keep,
    );
  }

  static Future<void> closeRight({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId anchor,
  }) async {
    final workbench = context.read<WorkbenchCubit>();
    final removed = workbench.closeRight(workspaceId, anchor);
    for (final tab in removed) {
      if (!context.mounted) return;
      await _closeDomainOnly(
        context: context,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        tab: tab,
      );
    }
  }

  static Future<void> closeAll({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
  }) async {
    final workbench = context.read<WorkbenchCubit>();
    final removed = workbench.closeAll(workspaceId);
    for (final tab in removed) {
      if (!context.mounted) return;
      await _closeDomainOnly(
        context: context,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        tab: tab,
      );
    }
  }

  static Future<void> closeReplacedPreview({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId? replaced,
  }) async {
    if (replaced == null) return;
    await _closeDomainOnly(
      context: context,
      workspaceId: workspaceId,
      tabScopeId: tabScopeId,
      tab: replaced,
    );
  }

  static Future<void> _closeDomainOnly({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId tab,
  }) async {
    final editor = context.read<EditorCubit>();
    switch (tab.kind) {
      case WorkbenchTabKind.session:
        // Teardown already routed by the bar close (onTabRemoved → chat.
        // teardownSession) for closeOthers/closeRight/closeAll.
        break;
      case WorkbenchTabKind.file:
        editor.closeFile(workspaceId, tab.id, force: true);
      case WorkbenchTabKind.diff:
        editor.closeDiff(workspaceId, tab.id);
      case WorkbenchTabKind.shell:
        disposeWorkbenchShellDomain(
          runService: context.read<WorkspaceTerminalRunService>(),
          group: context.read<WorkspaceTerminalRegistry>().groupFor(tabScopeId),
          entryId: tab.id,
        );
      case WorkbenchTabKind.run:
        await context.read<RunCubit>().dismissSession(tab.id);
    }
  }

  static RunSession? _runSessionById(List<RunSession> sessions, String id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  static Future<bool?> _confirmDiscard(BuildContext context) =>
      confirmEditorUnsavedDiscard(context);
}

/// Shared dirty-file discard prompt used by workbench and floating close.
Future<bool?> confirmEditorUnsavedDiscard(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.editorUnsavedChangesTitle),
          const SizedBox(height: 16),
          Text(l10n.editorUnsavedChangesDiscardMultiple(1)),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.editorDiscard),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
