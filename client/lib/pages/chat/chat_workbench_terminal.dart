import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../services/selection_ai/selection_ai_context.dart';
import '../../services/selection_ai/selection_ask_ai.dart';
import '../../services/selection_ai/selection_ask_ai_fab_host.dart';
import '../../services/io/filesystem.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_uri_opener.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace_dnd/terminal_drop_ingestor.dart';
import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../../utils/team/team_member_naming.dart';
import '../../widgets/follow_up/terminal_follow_up_compose.dart';
import '../../widgets/terminal/parked_send_overlay.dart';
import '../../widgets/terminal/teampilot_alacritty_terminal.dart';
import '../../widgets/terminal_find_bar.dart';
import '../../widgets/workspace_dnd/external_file_drop_region.dart';
import '../../widgets/workspace_dnd/workspace_file_drop_region.dart';
import '../home_workspace/workspace/workspace_session_actions.dart';
import 'chat_workbench_context_menu.dart';

class ChatWorkbenchRunningTerminal extends StatefulWidget {
  const ChatWorkbenchRunningTerminal({
    required this.session,
    required this.terminalTheme,
    required this.terminalController,
    required this.findVisible,
    required this.onFindVisibleChanged,
    required this.onControllerSearchChanged,
    required this.onOpenLink,
    required this.onDisconnect,
    required this.onRestart,
    this.appSession,
    this.historyMemberId = '',
    this.team,
    this.autofocus = true,
    super.key,
  });

  final TerminalSession session;
  final TerminalTheme terminalTheme;
  final TerminalController terminalController;
  final bool findVisible;
  final ValueChanged<bool> onFindVisibleChanged;
  final VoidCallback onControllerSearchChanged;
  final Future<void> Function(String uri) onOpenLink;
  final VoidCallback onDisconnect;
  final Future<void> Function() onRestart;
  final AppSession? appSession;
  final String historyMemberId;
  final TeamProfile? team;
  final bool autofocus;

  @override
  State<ChatWorkbenchRunningTerminal> createState() =>
      _ChatWorkbenchRunningTerminalState();
}

class _ChatWorkbenchRunningTerminalState
    extends State<ChatWorkbenchRunningTerminal> {
  final ValueNotifier<bool> _menuOpen = ValueNotifier(false);

  @override
  void dispose() {
    _menuOpen.dispose();
    super.dispose();
  }

  /// Fresh per-build ingestor for a drop region — stateless, captures the
  /// session's current namespace + CLI paste behavior.
  TerminalDropIngestor _dropIngestor() => TerminalDropIngestor(
    sink: widget.session.input,
    target: widget.session.runtimeTarget,
    behavior: widget.session.pathDropBehavior,
  );

  void _showDropOutcome(BuildContext context, DropOutcome outcome) {
    if (outcome.anyRejected && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.terminalDropCrossMachineRejected)),
      );
    }
  }

  ({String surfaceLabel, Workspace? workspace, String tabScopeId})
  _selectionAiTarget(BuildContext context) {
    final chat = context.read<ChatCubit>();
    final sessionId = chat.activeTab?.info.id.trim() ?? '';
    AppSession? appSession;
    for (final candidate in chat.state.sessions) {
      if (candidate.sessionId == sessionId) {
        appSession = candidate;
        break;
      }
    }

    final memberId = chat.activeTab?.selectedMemberId.trim() ?? '';
    String taskId = '';
    if (appSession != null) {
      for (final binding in appSession.members) {
        if (binding.rosterMemberId == memberId) {
          taskId = binding.taskId.trim();
          break;
        }
      }
    }

    String memberName = '';
    final teamId = appSession?.sessionTeam.trim() ?? '';
    if (appSession != null && teamId.isNotEmpty) {
      final profile = context.read<LaunchProfileCubit>().byId(teamId);
      if (profile is TeamProfile) {
        for (final member in sessionRosterMembers(appSession, profile)) {
          if (member.id == memberId) {
            memberName = member.name.trim();
            break;
          }
        }
      }
    }

    final effectiveSessionId = appSession?.sessionId.trim().isNotEmpty == true
        ? appSession!.sessionId.trim()
        : sessionId;
    final memberLabel = memberName.isNotEmpty
        ? memberName
        : taskId.isNotEmpty
        ? taskId
        : memberId.isNotEmpty
        ? memberId
        : effectiveSessionId;
    final workspaceId = appSession?.workspaceId.trim().isNotEmpty == true
        ? appSession!.workspaceId.trim()
        : chat.tabStore.activeWorkspaceId.trim();
    Workspace? workspace;
    for (final candidate in chat.state.workspaces) {
      if (candidate.workspaceId == workspaceId) {
        workspace = candidate;
        break;
      }
    }
    return (
      surfaceLabel: 'session/$effectiveSessionId/$memberLabel',
      workspace: workspace,
      tabScopeId: workspaceId,
    );
  }

  Future<void> _openAskAi(BuildContext context, String aiContext) {
    final target = _selectionAiTarget(context);
    final workspace = target.workspace;
    if (workspace == null || aiContext.trim().isEmpty || !mounted) {
      return Future.value();
    }
    return SelectionAskAi.openComposeDialog(
      context,
      aiContext: aiContext,
      workspace: workspace,
      tabScopeId: target.tabScopeId,
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    CellOffset? offset,
  ) async {
    final target = _selectionAiTarget(context);
    _menuOpen.value = true;
    try {
      await showChatWorkbenchTerminalContextMenu(
        context: context,
        menuContext: context,
        terminalController: widget.terminalController,
        globalPosition: details.globalPosition,
        engine: widget.session.engine,
        cellOffset: offset,
        sessionRunning: widget.session.isRunning,
        onFindRequested: () => widget.onFindVisibleChanged(true),
        onOpenLink: widget.onOpenLink,
        onExportScrollback: () => exportChatWorkbenchTerminalScrollback(
          context,
          widget.session.engine,
        ),
        onDisconnect: widget.onDisconnect,
        onRestart: widget.onRestart,
        aiSurfaceLabel: target.surfaceLabel,
        workspace: target.workspace,
        tabScopeId: target.tabScopeId,
      );
    } finally {
      if (mounted) _menuOpen.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TerminalFindShortcuts(
      findVisible: widget.findVisible,
      onToggleFind: () => widget.onFindVisibleChanged(true),
      onFindNext: () {
        widget.terminalController.searchNext();
        widget.onControllerSearchChanged();
      },
      onFindPrevious: () {
        widget.terminalController.searchPrev();
        widget.onControllerSearchChanged();
      },
      onCloseFind: () {
        widget.terminalController.searchClear();
        widget.onFindVisibleChanged(false);
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _menuOpen,
        child: Stack(
          children: [
            ExternalFileDropRegion(
              target: _dropIngestor(),
              onOutcome: (outcome) => _showDropOutcome(context, outcome),
              child: WorkspaceFileDropRegion(
                target: _dropIngestor(),
                onOutcome: (outcome) => _showDropOutcome(context, outcome),
                child: TeampilotAlacrittyTerminal(
                  engine: widget.session.engine,
                  controller: widget.terminalController,
                  theme: widget.terminalTheme,
                  // Chat workbench keeps the wider inset (dock shell uses 8).
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 16,
                  ),
                  autofocus: widget.autofocus && !widget.findVisible,
                  linkProviders: widget.session.linkProviders,
                  onPtyResize: widget.session.onTerminalPtyResize,
                  onTapDown: (_, offset) {
                    if (!HardwareKeyboard.instance.isControlPressed &&
                        !HardwareKeyboard.instance.isMetaPressed) {
                      widget.terminalController.clearSelection();
                    }
                  },
                  onLinkActivate: (uri) {
                    unawaited(widget.onOpenLink(uri));
                  },
                  onSecondaryTapDown: (details, offset) {
                    unawaited(_showContextMenu(context, details, offset));
                  },
                ),
              ),
            ),
            if (widget.findVisible)
              Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: TerminalFindBar(
                  engine: widget.session.engine,
                  controller: widget.terminalController,
                  searchLabel: context.l10n.terminalFind,
                  noResultsLabel: context.l10n.terminalFindNoResults,
                  onClose: () {
                    widget.terminalController.searchClear();
                    widget.onFindVisibleChanged(false);
                  },
                ),
              ),
            ParkedSendOverlay(
              submissions: widget.session.parkedUserSubmissions,
              isUnread: widget.session.isUnreadParkedMessage,
            ),
            if (widget.appSession != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TerminalFollowUpComposeHost(
                  session: widget.appSession!,
                  selectedMemberId: widget.historyMemberId,
                  team: widget.team,
                ),
              ),
          ],
        ),
        builder: (context, menuOpen, child) {
          return SelectionAskAiFabHost(
            listenable: widget.terminalController,
            selectionActive: () => widget.terminalController.selectionActive,
            readAiContext: () => buildTerminalAiContextClipboardText(
              surfaceLabel: _selectionAiTarget(context).surfaceLabel,
              text: widget.terminalController.readSelectionText() ?? '',
            ),
            onAskAi: (aiContext) => _openAskAi(context, aiContext),
            menuOpen: menuOpen,
            child: child!,
          );
        },
      ),
    );
  }
}

Future<void> openChatWorkbenchTerminalLink({
  required String link,
  required ChatCubit chatCubit,
  required WorkbenchEditorOpener editorOpener,
  required String workspaceId,
  required bool Function() isMounted,
  Filesystem? fs,
}) async {
  await TerminalUriOpener.open(
    link,
    workingDirectory: chatCubit.activeTabWorkingDirectory,
    fs: fs,
    openInEditor: (path) async {
      if (!isMounted()) return;
      await editorOpener.openFile(workspaceId, path, fs: fs);
    },
  );
}

void consumeChatWorkbenchRouteSession({
  required String? routeSessionId,
  required bool handledRouteSession,
  required ChatState state,
  required ChatCubit chatCubit,
  required LaunchProfileCubit teamCubit,
  required SessionRepository sessionRepo,
  required AppLocalizations l10n,
  required void Function(bool handled) onHandled,
  bool connectImmediately = false,
}) {
  if (routeSessionId == null || handledRouteSession) return;

  AppSession? session;
  for (final s in state.sessions) {
    if (s.sessionId == routeSessionId) {
      session = s;
      break;
    }
  }
  if (session == null) return;

  onHandled(true);

  if (chatCubit.tabStore.openTabBySessionId(routeSessionId) != null) {
    return;
  }

  if (session.sessionTeam.trim().isEmpty) {
    unawaited(
      chatCubit.requestOpenSession(
        buildOpenExistingSessionRequest(
          session: session,
          repo: sessionRepo,
          emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
          connectImmediately: connectImmediately,
        ),
      ),
    );
    return;
  }

  final teamId = session.sessionTeam.trim();
  final profile = teamCubit.byId(teamId);
  if (profile is! TeamProfile) {
    chatCubit.addSystemMessage(l10n.sessionLaunchMissingTeamMember);
    return;
  }
  TeamMemberConfig? lead;
  for (final member in profile.members) {
    if (TeamMemberNaming.isTeamLead(member)) {
      lead = member;
      break;
    }
  }
  if (lead == null) {
    chatCubit.addSystemMessage(l10n.sessionLaunchMissingTeamMember);
    return;
  }

  unawaited(chatCubit.scheduleTeamConfigValidation(profile));
  unawaited(
    chatCubit.requestOpenSession(
      buildOpenExistingSessionRequest(
        session: session,
        team: profile,
        member: lead,
        repo: sessionRepo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        connectImmediately: connectImmediately,
      ),
    ),
  );
}

/// Stable key for the chat workbench terminal stack.
///
/// Kept independent of loading/running so the [TerminalView] element is not
/// remounted when connect finishes — only visibility toggles via [Offstage].
const Key kChatWorkbenchTerminalStackKey = ValueKey('chat-terminal-running');

/// Legacy helper for tests that still key off loading vs running transitions.
Key chatWorkbenchTerminalViewKey({
  required bool loading,
  required bool running,
}) {
  if (loading) return const ValueKey('chat-terminal-loading');
  if (running) return const ValueKey('chat-terminal-running');
  return const ValueKey('chat-terminal-placeholder');
}

TerminalController bindChatWorkbenchTerminalController(
  TerminalController current,
  TerminalEngine engine,
) {
  if (identical(current.engine, engine)) return current;
  if (current.engine != null) {
    current.dispose();
    current = TerminalController();
  }
  current.attach(engine);
  return current;
}
