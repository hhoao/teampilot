import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import 'package:shared_ui/shared_ui.dart';

/// Tab-bar actions for the unified workbench (session / file / diff).
abstract final class WorkbenchShellActions {
  WorkbenchShellActions._();

  static Future<void> select({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId tab,
  }) async {
    final workbench = context.read<WorkbenchCubit>();
    final chat = context.read<ChatCubit>();
    workbench.select(workspaceId, tab);
    if (chat.state.composeActive) {
      chat.exitComposeMode();
    }
    if (tab.kind == WorkbenchTabKind.session) {
      final tabs = chat.tabStore.tabsForWorkspace(tabScopeId);
      final index = tabs.indexWhere((t) => t.info.id == tab.id);
      if (index >= 0) chat.selectTab(index);
    }
  }

  static Future<void> closeAt({
    required BuildContext context,
    required String workspaceId,
    required String tabScopeId,
    required WorkbenchTabId tab,
  }) async {
    final workbench = context.read<WorkbenchCubit>();
    final chat = context.read<ChatCubit>();
    final editor = context.read<EditorCubit>();

    switch (tab.kind) {
      case WorkbenchTabKind.session:
        final tabs = chat.tabStore.tabsForWorkspace(tabScopeId);
        final index = tabs.indexWhere((t) => t.info.id == tab.id);
        if (index >= 0) chat.closeTab(index);
        workbench.removeTab(workspaceId, tab);
      case WorkbenchTabKind.file:
        final dirty = editor.state.bucket(workspaceId).isDirty(tab.id);
        if (dirty) {
          final discard = await _confirmDiscard(context);
          if (discard != true || !context.mounted) return;
        }
        editor.closeFile(workspaceId, tab.id, force: true);
        workbench.removeTab(workspaceId, tab);
      case WorkbenchTabKind.diff:
        editor.closeDiff(workspaceId, tab.id);
        workbench.removeTab(workspaceId, tab);
      case WorkbenchTabKind.shell:
      case WorkbenchTabKind.run:
        workbench.removeTab(workspaceId, tab);
    }
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
    final chat = context.read<ChatCubit>();
    final editor = context.read<EditorCubit>();
    switch (tab.kind) {
      case WorkbenchTabKind.session:
        final tabs = chat.tabStore.tabsForWorkspace(tabScopeId);
        final index = tabs.indexWhere((t) => t.info.id == tab.id);
        if (index >= 0) chat.closeTab(index);
      case WorkbenchTabKind.file:
        editor.closeFile(workspaceId, tab.id, force: true);
      case WorkbenchTabKind.diff:
        editor.closeDiff(workspaceId, tab.id);
      case WorkbenchTabKind.shell:
      case WorkbenchTabKind.run:
        break;
    }
  }

  static Future<bool?> _confirmDiscard(BuildContext context) {
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
}
