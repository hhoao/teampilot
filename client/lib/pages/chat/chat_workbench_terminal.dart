import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_uri_opener.dart';
import '../../services/terminal/terminal_fonts.dart';
import '../../services/workspace_dnd/terminal_drop_ingestor.dart';
import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../../widgets/terminal/parked_send_overlay.dart';
import '../../widgets/terminal_find_bar.dart';
import '../../widgets/workspace_dnd/external_file_drop_region.dart';
import '../../widgets/workspace_dnd/workspace_file_drop_region.dart';
import 'chat_workbench_context_menu.dart';

class ChatWorkbenchRunningTerminal extends StatelessWidget {
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

  /// Fresh per-build ingestor for a drop region — stateless, captures the
  /// session's current namespace + CLI paste behavior.
  TerminalDropIngestor _dropIngestor() => TerminalDropIngestor(
    sink: session,
    target: session.runtimeTarget,
    behavior: session.pathDropBehavior,
  );

  void _showDropOutcome(BuildContext context, DropOutcome outcome) {
    if (outcome.anyRejected && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.terminalDropCrossMachineRejected)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TerminalFindShortcuts(
      findVisible: findVisible,
      onToggleFind: () => onFindVisibleChanged(true),
      onFindNext: () {
        terminalController.searchNext();
        onControllerSearchChanged();
      },
      onFindPrevious: () {
        terminalController.searchPrev();
        onControllerSearchChanged();
      },
      onCloseFind: () {
        terminalController.searchClear();
        onFindVisibleChanged(false);
      },
      child: Stack(
        children: [
          ExternalFileDropRegion(
            target: _dropIngestor(),
            onOutcome: (outcome) => _showDropOutcome(context, outcome),
            child: WorkspaceFileDropRegion(
            target: _dropIngestor(),
            onOutcome: (outcome) => _showDropOutcome(context, outcome),
            child: TerminalView(
              session.engine,
              controller: terminalController,
            theme: terminalTheme,
            backgroundOpacity: 0.98,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
            textStyle: appTerminalTextStyle(context),
            autofocus: !findVisible,
            linkProviders: session.linkProviders,
            primaryTapActivatesLink: context
                .watch<SessionPreferencesCubit>()
                .state
                .preferences
                .terminalLinkClickOpensInApp,
            onViewportResize: session.onViewportResize,
            onTapDown: (_, offset) {
              if (!HardwareKeyboard.instance.isControlPressed &&
                  !HardwareKeyboard.instance.isMetaPressed) {
                terminalController.clearSelection();
              }
            },
            onLinkActivate: (uri) {
              unawaited(onOpenLink(uri));
            },
            onSecondaryTapDown: (details, offset) {
              unawaited(
                showChatWorkbenchTerminalContextMenu(
                  context: context,
                  menuContext: context,
                  terminalController: terminalController,
                  globalPosition: details.globalPosition,
                  engine: session.engine,
                  cellOffset: offset,
                  sessionRunning: session.isRunning,
                  onFindRequested: () => onFindVisibleChanged(true),
                  onOpenLink: onOpenLink,
                  onExportScrollback: () =>
                      exportChatWorkbenchTerminalScrollback(
                        context,
                        session.engine,
                      ),
                  onDisconnect: onDisconnect,
                  onRestart: onRestart,
                ),
              );
            },
            ),
          ),
          ),
          if (findVisible)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: TerminalFindBar(
                engine: session.engine,
                controller: terminalController,
                searchLabel: context.l10n.terminalFind,
                noResultsLabel: context.l10n.terminalFindNoResults,
                onClose: () {
                  terminalController.searchClear();
                  onFindVisibleChanged(false);
                },
              ),
            ),
          ParkedSendOverlay(
            submissions: session.parkedUserSubmissions,
            isUnread: session.isUnreadParkedMessage,
          ),
        ],
      ),
    );
  }
}

Future<void> openChatWorkbenchTerminalLink({
  required String link,
  required ChatCubit chatCubit,
  required EditorCubit editorCubit,
  required bool Function() isMounted,
}) async {
  await TerminalUriOpener.open(
    link,
    workingDirectory: chatCubit.activeTabWorkingDirectory,
    openInEditor: (path) async {
      if (!isMounted()) return;
      await editorCubit.openFile(path);
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
  chatCubit.selectSession(session.sessionId);

  final team = teamCubit.state.selectedTeam;
  final lead = team != null
      ? team.members.where((m) => m.id == 'team-lead').toList()
      : <TeamMemberConfig>[];
  if (team != null && lead.isNotEmpty) {
    unawaited(
      chatCubit.openSessionTab(
        session,
        team: team,
        member: lead.first,
        repo: sessionRepo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
  } else {
    unawaited(
      chatCubit.openSessionTab(
        session,
        repo: sessionRepo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
    if (team != null) {
      chatCubit.addSystemMessage(
        'FlashskyAI requires a member named team-lead.',
      );
    }
  }
}

/// Key for the `AnimatedSwitcher` terminal child in the chat workbench.
///
/// The running terminal uses a STABLE key (independent of which session/member
/// is shown) so switching members reuses the same `TerminalView` element. That
/// triggers the submodule's engine-swap path (`didUpdateWidget`) instead of a
/// remount, keeping the glyph cache and viewport geometry warm — otherwise a
/// freshly mounted `TerminalView` paints partial text while its empty glyph
/// cache warms up over several frames. Loading / placeholder keep their own
/// keys so transitions to/from them still cross-fade.
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
