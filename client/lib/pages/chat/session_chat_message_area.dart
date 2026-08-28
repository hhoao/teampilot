import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../services/ai_history/special_tool_resolvers.dart';
import '../../services/ai_history/workspace_edit_line_highlighter.dart';
import '../../services/cli/registry/capabilities/ai_history_capability.dart';
import '../../services/cli/tasks/cli_task_board_controller.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import '../../services/workbench/ai_tool_file_open_coordinator.dart';
import '../../services/workbench/session_member_filesystem.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'ai_message_strings_from_l10n.dart';
import 'chat_find_bar.dart';
import 'chat_outline.dart';
import 'chat_outline_rail.dart';
import 'chat_reveal_controller.dart';
import 'session_chat_markdown_link_scope.dart';
import 'session_history_live_chrome.dart';
import 'session_history_review_messages.dart';
import 'subagent_preview_controller.dart';

/// The scrollable message thread area of a session chat view.
///
/// Displays [SessionHistoryReviewMessages], subagent preview overlay, task board
/// panel, and find bar overlay. The compose section is kept in the parent.
class SessionChatMessageArea extends StatelessWidget {
  const SessionChatMessageArea({
    required this.session,
    required this.workspace,
    required this.selectedMemberId,
    required this.shellMemberId,
    required this.isSubmitting,
    required this.state,
    required this.historySeat,
    required this.top,
    required this.previewTitle,
    required this.subagentPreview,
    required this.taskBoardController,
    required this.findVisible,
    required this.highlightMessageId,
    required this.visibleOwnerId,
    required this.onLocateOutline,
    required this.findController,
    required this.findQueryController,
    required this.findFocusNode,
    required this.revealController,
    required this.historyCap,
    required this.onRetry,
    required this.onRetryFailedMessage,
    required this.onCloseFind,
    required this.onNavigateFind,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String selectedMemberId;
  final String shellMemberId;
  final bool isSubmitting;
  final AiHistoryState state;
  final AiHistorySeat historySeat;
  final AiSubagentAttachment? top;
  final String previewTitle;
  final SubagentPreviewController subagentPreview;
  final CliTaskBoardController? taskBoardController;
  final bool findVisible;
  final String? highlightMessageId;
  final ValueNotifier<String?> visibleOwnerId;
  final ValueChanged<ChatOutlineEntry> onLocateOutline;
  final ChatTranscriptFindController findController;
  final TextEditingController findQueryController;
  final FocusNode findFocusNode;
  final ChatRevealController revealController;
  final AiHistoryCapability? historyCap;
  final VoidCallback onRetry;
  final ValueChanged<String> onRetryFailedMessage;
  final VoidCallback onCloseFind;
  final void Function(TranscriptHit) onNavigateFind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final cs = Theme.of(context).colorScheme;
    final lifecycle = context.read<ChatCubit>().lifecycle;
    final prefs = context
        .select<
          LayoutCubit,
          ({
            ContentDisplayMode userMessageMode,
            ContentDisplayMode chatCodeBlockMode,
          })
        >(
          (c) => (
            userMessageMode: c.state.preferences.chatUserMessageMode,
            chatCodeBlockMode: c.state.preferences.chatCodeBlockMode,
          ),
        );
    final foldCategories = context.select<LayoutCubit, Set<AiToolCallCategory>>(
      (c) => c.state.preferences.foldToolCallCategories,
    );

    final launchContext = WorkspaceLaunchContext(
      session: session,
      workspace: workspace,
    );

    final work = session.workDirsForMember(
      selectedMemberId,
      folders: launchContext.folderCatalog,
    );
    final workspaceRoot = work.workingDirectory.isNotEmpty
        ? work.workingDirectory
        : session.firstFolderPath;
    final sessionWorkingDirectory = workspaceRoot.isEmpty
        ? null
        : workspaceRoot;

    final workspaceFolderPaths = sessionMemberFolderPaths(
      lifecycle: lifecycle,
      launchContext: launchContext,
      memberId: selectedMemberId,
    );
    final hrefRoots = [
      if (sessionWorkingDirectory != null) sessionWorkingDirectory,
      ...workspaceFolderPaths,
    ];

    // Promote to local so the ternary below can promote to non-null.
    final cap = historyCap;

    final registry = CliToolRegistryScope.of(context);
    final toolResolvers = registry.capability<AiHistoryCapability>(
      session.cli ?? CliTool.claude,
    );

    return Expanded(
      // Full-bleed scroll surface: margins beside the text
      // column still receive wheel / drag. Message width is
      // capped inside SessionHistoryThread.
      child: Stack(
        children: [
          Positioned.fill(
            child: SessionChatMarkdownLinkScope(
              session: session,
              workspace: workspace,
              selectedMemberId: selectedMemberId,
              hrefRoots: hrefRoots,
              child: AiToolFileActionsScope(
                actions: AiToolFileActions(
                  fileResolver:
                      toolResolvers?.fileResolver ?? _noopFileResolver,
                  editResolver:
                      toolResolvers?.editResolver ?? _noopEditResolver,
                  shellResolver:
                      toolResolvers?.shellResolver ?? _noopShellResolver,
                  onOpenFile: (target) async {
                    final fs = await resolveSessionMemberFilesystem(
                      lifecycle: lifecycle,
                      launchContext: launchContext,
                      memberId: selectedMemberId,
                      toolsScope: WorkspaceToolsScope.maybeOf(context),
                    );
                    if (!context.mounted) return;
                    final coordinator = AiToolFileOpenCoordinator(
                      opener: context.read<WorkbenchEditorOpener>(),
                      editor: context.read<EditorCubit>(),
                    );
                    final result = await coordinator.openToolFile(
                      workspaceId: session.workspaceId,
                      target: target,
                      sessionWorkingDirectory: sessionWorkingDirectory,
                      workspaceFolderPaths: workspaceFolderPaths,
                      fs: fs,
                    );
                    if (!context.mounted) return;
                    if (result.isMissing) {
                      AppToast.show(
                        context,
                        message: l10n.aiToolFileNotFound(target.path),
                        variant: TpToastVariant.warning,
                      );
                    }
                  },
                  lineHighlighter: WorkspaceAiEditLineHighlighter(
                    brightness: Theme.of(context).brightness,
                  ),
                ),
                child: AiToolSubagentActionsScope(
                  actions: AiToolSubagentActions(
                    isSubagentTool: cap == null
                        ? null
                        : (name) => cap.subagentToolNames.contains(
                            name.trim().toLowerCase(),
                          ),
                    onOpenSubagent: (id) async {
                      final attachments = historySeat.subagentAttachments;
                      if (!attachments.containsKey(id)) {
                        if (!context.mounted) return;
                        AppToast.show(
                          context,
                          message: l10n.subagentPreviewUnavailable,
                          variant: TpToastVariant.warning,
                        );
                        return;
                      }
                      subagentPreview.push(id);
                    },
                  ),
                  child: AiSpecialToolActionsScope(
                    actions: AiSpecialToolActions(
                      taskResolver: TranscriptAiTaskToolResolver(
                        contentById:
                            taskBoardController?.board.contentById ?? const {},
                      ),
                      askUserResolver: const TranscriptAiAskUserResolver(),
                      workflowResolver: AttachmentAiWorkflowResolver(
                        attachments: historySeat.subagentAttachments,
                      ),
                    ),
                    child: AiMessageStringsScope(
                      strings: aiMessageStringsFromL10n(l10n),
                      child: AiToolCallFoldScope(
                        shouldFold: (part) =>
                            foldCategories.contains(part.category),
                        child: Stack(
                          children: [
                            Builder(
                              builder: (context) {
                                // Read ChatCubit imperatively — no
                                // context.select dependency. Enclosing
                                // AiHistorySeat BlocBuilder already
                                // rebuilds when awaitingAssistant
                                // changes (synced with working state).
                                final cubit = context.read<ChatCubit>();
                                final sid = session.sessionId;
                                final sessionWorking = cubit
                                    .state
                                    .workingSessionIds
                                    .contains(sid);
                                final sessionConnecting =
                                    cubit.podFor(sid)?.phase.isLaunching ??
                                    false;
                                final memberRunning = cubit.isMemberRunning(
                                  sessionId: sid,
                                  memberId: shellMemberId,
                                );
                                final liveChrome =
                                    SessionHistoryLiveChromeX.resolve(
                                      turnInFlight: historyTurnInFlight(
                                        isSubmitting: isSubmitting,
                                        awaitingAssistant:
                                            state.awaitingAssistant,
                                        sessionWorking: sessionWorking,
                                        userStoppedTurn: false,
                                      ),
                                      memberRunning: memberRunning,
                                      sessionWorking: sessionWorking,
                                      sessionConnecting: sessionConnecting,
                                    );
                                return MarkdownDisplayModeScope(
                                  userMessageMode: prefs.userMessageMode,
                                  codeBlockMode: prefs.chatCodeBlockMode,
                                  child: SessionHistoryReviewMessages(
                                    state: state,
                                    runtime: historySeat.runtime,
                                    onRetry: onRetry,
                                    onLoadOlder: historySeat.loadOlder,
                                    liveChrome: liveChrome,
                                    pendingDeliveryStatuses:
                                        historySeat.pendingDeliveryStatuses,
                                    onRetryFailedMessage: onRetryFailedMessage,
                                    highlightMessageId: highlightMessageId,
                                    revealRequest: revealController,
                                    visibleOwnerId: visibleOwnerId,
                                  ),
                                );
                              },
                            ),
                            _ChatOutlineLayer(
                              historySeat: historySeat,
                              subagentPreviewOpen: top != null,
                              visibleOwnerId: visibleOwnerId,
                              onLocate: onLocateOutline,
                            ),
                            if (top != null)
                              Positioned.fill(
                                child: Material(
                                  color: cs.surface,
                                  child: AiHistoryRenderScope(
                                    // History-review budget also
                                    // guards subagent messages: a
                                    // giant subagent turn collapses
                                    // instead of freezing the
                                    // preview open.
                                    child: SubagentPreviewScaffold(
                                      title: previewTitle,
                                      messages: top!.messages,
                                      emptyLabel: l10n.subagentPreviewEmpty,
                                      backTooltip: l10n.subagentPreviewBack,
                                      onBack: subagentPreview.popAndStopFollow,
                                    ),
                                  ),
                                ),
                              ),
                            if (taskBoardController != null)
                              Positioned(
                                top: spacing.sm,
                                right: spacing.sm,
                                child: ListenableBuilder(
                                  listenable: taskBoardController!,
                                  builder: (context, _) {
                                    final board = taskBoardController!.board;
                                    if (board.totalCount == 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return AiTaskBoardPanel(
                                      items: board.aiItems,
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (findVisible)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ChatFindBar(
                controller: findController,
                queryController: findQueryController,
                focusNode: findFocusNode,
                onNavigate: onNavigateFind,
                onClose: onCloseFind,
              ),
            ),
        ],
      ),
    );
  }
}

const _noopFileResolver = _NoopFileResolver();
const _noopEditResolver = _NoopEditResolver();
const _noopShellResolver = _NoopShellResolver();

class _NoopFileResolver implements AiToolFileTargetResolver {
  const _NoopFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

class _NoopEditResolver implements AiEditToolTargetResolver {
  const _NoopEditResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) => null;
}

class _NoopShellResolver implements AiShellToolTargetResolver {
  const _NoopShellResolver();

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) => null;
}

class _ChatOutlineLayer extends StatefulWidget {
  const _ChatOutlineLayer({
    required this.historySeat,
    required this.subagentPreviewOpen,
    required this.visibleOwnerId,
    required this.onLocate,
  });

  final AiHistorySeat historySeat;
  final bool subagentPreviewOpen;
  final ValueNotifier<String?> visibleOwnerId;
  final ValueChanged<ChatOutlineEntry> onLocate;

  @override
  State<_ChatOutlineLayer> createState() => _ChatOutlineLayerState();
}

class _ChatOutlineLayerState extends State<_ChatOutlineLayer> {
  List<ChatOutlineEntry> _outline = const [];
  StreamSubscription<void>? _runtimeSub;
  StreamSubscription<AiHistoryState>? _seatSub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ChatOutlineLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.historySeat != widget.historySeat) {
      _unlisten();
      _outline = const [];
      _listen();
    }
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  void _listen() {
    _runtimeSub = widget.historySeat.runtime.changes.listen((_) => _refresh());
    _seatSub = widget.historySeat.stream.listen((_) => _refresh());
  }

  void _unlisten() {
    unawaited(_runtimeSub?.cancel() ?? Future<void>.value());
    unawaited(_seatSub?.cancel() ?? Future<void>.value());
    _runtimeSub = null;
    _seatSub = null;
  }

  void _refresh() {
    if (!mounted) return;
    final next = buildChatOutline(
      widget.historySeat.loadedMessages,
      emptyPreview: context.l10n.chatUserMessageRailEmptyPreview,
      previous: _outline,
    );
    if (identical(next, _outline)) return;
    setState(() => _outline = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final next = buildChatOutline(
      widget.historySeat.loadedMessages,
      emptyPreview: l10n.chatUserMessageRailEmptyPreview,
      previous: _outline,
    );
    _outline = next;
    return ChatOutlineHost(
      show: shouldShowChatOutline(
        threadVisible: true,
        subagentPreviewOpen: widget.subagentPreviewOpen,
        entries: _outline,
      ),
      entries: _outline,
      activeId: widget.visibleOwnerId,
      onLocate: widget.onLocate,
      semanticLabelFor: l10n.chatUserMessageRailSemanticLabel,
    );
  }
}
