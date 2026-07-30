import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
import '../../models/run/run_ui_intent.dart';
import 'workbench_shell_launcher.dart';

/// Maps a [RunUiIntent] to the center-strip run tab to activate, or null when
/// the intent should not switch the active tool surface.
///
/// Terminal / shell intents use the floating workspace surface — see
/// [resolveFloatingTabForTerminalRunIntent].
WorkbenchTabId? resolveWorkbenchTabForRunIntent(
  RunUiIntent intent, {
  required String? latestRunSessionId,
}) {
  if (!intent.activateToolWindow) return null;
  switch (intent.surface) {
    case RunToolSurface.terminal:
      return null;
    case RunToolSurface.run:
      final id = latestRunSessionId?.trim();
      if (id == null || id.isEmpty) return null;
      return WorkbenchTabId.run(id);
  }
}

/// Floating terminal tab for a run→terminal [RunUiIntent], or null when the
/// intent should not open/focus a shell tab.
FloatingTab? resolveFloatingTabForTerminalRunIntent(
  RunUiIntent intent, {
  required String entryTitle,
}) {
  if (!intent.activateToolWindow) return null;
  if (intent.surface != RunToolSurface.terminal) return null;
  final id = intent.terminalEntryId?.trim();
  if (id == null || id.isEmpty) return null;
  final title = entryTitle.trim().isNotEmpty ? entryTitle.trim() : id;
  return FloatingTab(
    id: floatingShellTabId(id),
    surfaceId: 'terminal',
    title: title,
    payload: id,
  );
}
