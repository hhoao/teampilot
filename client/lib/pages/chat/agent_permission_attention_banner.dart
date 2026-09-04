import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/agent_status/agent_attention_state.dart';
import '../../services/agent_status/ask_user_question_policy.dart';
import '../../services/agent_status/exit_plan_mode.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/chat_interaction_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/compose/compose_at_file_refs.dart';
import '../../services/terminal/ask_user_question_answer_service.dart';
import '../../services/terminal/exit_plan_mode_approval_service.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../utils/ui/app_keys.dart';
import 'ai_message_strings_from_l10n.dart';
import 'session_seat_working.dart';

/// Compact card shown just above Chat compose when the seat needs Terminal
/// confirmation. Does not auto-switch; CTA jumps to Terminal.
class AgentPermissionAttentionBanner extends StatelessWidget {
  const AgentPermissionAttentionBanner({
    required this.session,
    required this.selectedMemberId,
    super.key,
  });

  final AppSession session;

  /// Scoped member for this chat body (not foreground [ChatCubit] selection).
  final String selectedMemberId;

  /// Seat id used for attention lookup (simple → [AppSession.sessionId]).
  static String attentionMemberId({
    required AppSession session,
    required String selectedMemberId,
  }) {
    if (session.isSimple) return session.sessionId;
    final mid = selectedMemberId.trim();
    return mid.isEmpty ? session.sessionId : mid;
  }

  /// Whether Chat compose should lock for the selected seat.
  static bool isSelectedSeatWaiting({
    required AgentAttentionCubit attention,
    required AppSession session,
    required String selectedMemberId,
  }) {
    final seatId = attentionMemberId(
      session: session,
      selectedMemberId: selectedMemberId,
    );
    return attention.state.attentionFor(
          sessionId: session.sessionId,
          memberId: seatId,
        ) ==
        AgentSeatAttention.waiting;
  }

  /// Whether the interactive ask-user / permission card is showing for the
  /// seat (compose should be hidden, not merely disabled).
  static bool isSelectedSeatAskCard({
    required AgentAttentionCubit attention,
    required AppSession session,
    required String selectedMemberId,
    required CliTool seatCli,
    CliToolRegistry? registry,
  }) {
    final seatId = attentionMemberId(
      session: session,
      selectedMemberId: selectedMemberId,
    );
    final entry = attention.state.entryFor(
      sessionId: session.sessionId,
      memberId: seatId,
    );
    if (entry == null || entry.attention != AgentSeatAttention.waiting) {
      return false;
    }
    final toolRegistry = registry ?? CliToolRegistry.builtIn();
    final capability = toolRegistry.capability<ChatInteractionCapability>(
      seatCli,
    );
    if (shouldShowAskUserQuestionCard(
      capability: capability,
      questions: entry.lastEvent?.askUserQuestions,
      askRequestId: entry.lastEvent?.askRequestId,
    )) {
      return true;
    }
    return shouldShowPermissionCard(
      capability: capability,
      permissionRequest: entry.lastEvent?.permissionRequest,
      askRequestId: entry.lastEvent?.askRequestId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = session.sessionId;
    final workbenchView = seatSelect<ChatCubit, SessionWorkbenchView>(context, (
      c,
    ) {
      final tab = c.tabStore.openTabBySessionId(sessionId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    });
    if (workbenchView != SessionWorkbenchView.chat) {
      return const SizedBox.shrink();
    }

    final seatId = attentionMemberId(
      session: session,
      selectedMemberId: selectedMemberId,
    );
    final entry = seatSelect<AgentAttentionCubit, AgentSeatAttentionEntry?>(
      context,
      (c) => c.state.entryFor(sessionId: sessionId, memberId: seatId),
    );
    if (entry == null || entry.attention != AgentSeatAttention.waiting) {
      return const SizedBox.shrink();
    }

    final questions = entry.lastEvent?.askUserQuestions;
    final askRequestId = entry.lastEvent?.askRequestId;
    final lockedCli = _resolveSeatCli(context, seatId: seatId);
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final capability = registry.capability<ChatInteractionCapability>(
      lockedCli,
    );
    final showAskCard = shouldShowAskUserQuestionCard(
      capability: capability,
      questions: questions,
      askRequestId: askRequestId,
    );
    if (showAskCard && questions != null) {
      return _withStrings(
        context,
        AiAskUserQuestionCard(
          questions: questions,
          externalError: entry.askReplyError,
          onSubmit: (submission) async {
            final result = await context
                .read<ChatCubit>()
                .answerAskUserQuestion(
                  sessionId: sessionId,
                  memberId: seatId,
                  optionIndex: submission.optionIndices.first,
                  optionIndices: submission.optionIndices,
                  askRequestId: askRequestId,
                  answers: submission.answers,
                  freeText: submission.freeText,
                  freeTexts: submission.freeTexts,
                );
            return _fromAskUser(result);
          },
          onCancel: () async {
            final result = await context
                .read<ChatCubit>()
                .cancelAskUserQuestion(
                  sessionId: sessionId,
                  memberId: seatId,
                  askRequestId: askRequestId,
                );
            return _fromAskUser(result);
          },
          onAnswerInTerminal: () => _openTerminal(
            context,
            sessionId: sessionId,
            seatId: seatId,
            selectedMemberId: selectedMemberId,
          ),
        ),
      );
    }

    final permissionRequest = entry.lastEvent?.permissionRequest;
    if (shouldShowPermissionCard(
          capability: capability,
          permissionRequest: permissionRequest,
          askRequestId: askRequestId,
        ) &&
        permissionRequest != null) {
      return _withStrings(
        context,
        AiPermissionCard(
          description: permissionRequest.description,
          showAlwaysAllow: permissionRequest.always.isNotEmpty,
          externalError: entry.askReplyError,
          onReply: (reply) async {
            final result = await context
                .read<ChatCubit>()
                .answerPermissionRequest(
                  sessionId: sessionId,
                  memberId: seatId,
                  permissionRequestId: askRequestId!,
                  reply: reply,
                );
            return _fromAskUser(result);
          },
          onAnswerInTerminal: () => _openTerminal(
            context,
            sessionId: sessionId,
            seatId: seatId,
            selectedMemberId: selectedMemberId,
          ),
        ),
      );
    }

    final lastEvent = entry.lastEvent;
    final planText = lastEvent?.planText?.trim() ?? '';
    final planFilePath = lastEvent?.planFilePath?.trim() ?? '';
    if (isExitPlanModeTool(lastEvent?.toolName) &&
        (planText.isNotEmpty || planFilePath.isNotEmpty)) {
      final exitPlanCapability = registry.capability<ChatInteractionCapability>(
        lockedCli,
      );
      final supportsInChatApproval =
          exitPlanCapability?.supportsInChatApproval ?? false;
      final toolUseId = lastEvent?.toolUseId?.trim() ?? '';
      // PermissionRequest plan confirmations carry no tool_use_id but are
      // held by ExitPlanPermissionRequestGate (seat-keyed), so they are
      // actionable from chat too.
      final isHeldPermissionRequest =
          lastEvent?.hookEventName == 'PermissionRequest';
      final inChatApproval =
          supportsInChatApproval &&
          (toolUseId.isNotEmpty || isHeldPermissionRequest);
      return _withStrings(
        context,
        AiExitPlanModeCard(
          planText: planText,
          planFilePath: planFilePath.isEmpty ? null : planFilePath,
          onApprove: inChatApproval
              ? () async {
                  final result = await context
                      .read<ChatCubit>()
                      .approveExitPlanMode(
                        sessionId: sessionId,
                        memberId: seatId,
                        toolUseId: toolUseId,
                        planText: planText,
                        planFilePath: planFilePath.isEmpty
                            ? null
                            : planFilePath,
                      );
                  return _fromExitPlan(result);
                }
              : null,
          onReject: inChatApproval
              ? () async {
                  final result = await context
                      .read<ChatCubit>()
                      .rejectExitPlanMode(
                        sessionId: sessionId,
                        memberId: seatId,
                        toolUseId: toolUseId,
                        planText: planText,
                        planFilePath: planFilePath.isEmpty
                            ? null
                            : planFilePath,
                      );
                  return _fromExitPlan(result);
                }
              : null,
          onOpenTerminal: () => _openTerminal(
            context,
            sessionId: sessionId,
            seatId: seatId,
            selectedMemberId: selectedMemberId,
          ),
          onOpenPlanFile: (path) {
            unawaited(
              context.read<WorkbenchEditorOpener>().openFile(
                session.workspaceId,
                path,
                preview: true,
                fs: filesystemForComposeAtFileOpen(path),
              ),
            );
          },
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final radius = TpTheme.of(context).control.radius;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AppKeys.agentPermissionAttentionBanner,
        elevation: 2,
        shadowColor: cs.shadow.withValues(alpha: 0.28),
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.md,
            spacing.sm,
            spacing.sm,
            spacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.front_hand_rounded, size: 16, color: cs.tertiary),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  l10n.agentPermissionAttentionBanner,
                  style: TpTextStyles.of(context).smColored(cs.onSurface),
                ),
              ),
              SizedBox(width: spacing.sm),
              TpButton(
                key: AppKeys.agentPermissionOpenTerminalButton,
                variant: TpButtonVariant.primary,
                size: TpControlSize.small,
                onPressed: () => _openTerminal(
                  context,
                  sessionId: sessionId,
                  seatId: seatId,
                  selectedMemberId: selectedMemberId,
                ),
                child: Text(l10n.agentPermissionOpenTerminal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seat CLI — same lock resolution as compose / turn interrupt.
  CliTool _resolveSeatCli(BuildContext context, {required String seatId}) {
    if (session.isSimple || session.sessionTeam.trim().isEmpty) {
      return session.cli ?? CliTool.claude;
    }

    TeamProfile? team;
    List<CliPreset> presets = const [];
    try {
      final teamId = session.sessionTeam.trim();
      final profile = context.read<LaunchProfileCubit>().byId(teamId);
      if (profile is TeamProfile) team = profile;
      presets = context.read<CliPresetsCubit>().state.presets;
    } catch (_) {
      // Tests / partial trees may omit profile cubits — fall back below.
    }
    if (team == null) return CliTool.claude;

    final memberId = selectedMemberId.trim().isNotEmpty
        ? selectedMemberId.trim()
        : seatId;
    return SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: team,
      memberId: memberId,
      globalPresets: presets,
      cliForMember: (t, id, {List<CliPreset> globalPresets = const []}) {
        TeamMemberConfig? member;
        for (final m in t.members) {
          if (m.id == id) {
            member = m;
            break;
          }
        }
        if (member != null) {
          return memberLaunchCli(
            team: t,
            member: member,
            globalPresets: globalPresets,
          );
        }
        return t.cli;
      },
    );
  }

  void _openTerminal(
    BuildContext context, {
    required String sessionId,
    required String seatId,
    required String selectedMemberId,
  }) {
    final chat = context.read<ChatCubit>();
    if (!session.isSimple &&
        seatId.isNotEmpty &&
        seatId != selectedMemberId.trim()) {
      chat.selectMember(seatId);
    }
    chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal);
  }

  Widget _withStrings(BuildContext context, Widget child) {
    return AiMessageStringsScope(
      strings: aiMessageStringsFromL10n(context.l10n),
      child: child,
    );
  }
}

AiInteractiveResult _fromAskUser(AskUserAnswerResult result) =>
    switch (result) {
      AskUserAnswerFailed(:final reason) => AiInteractiveFailed(reason),
      AskUserAnswerOk() => const AiInteractiveOk(),
    };

AiInteractiveResult _fromExitPlan(ExitPlanApprovalResult result) =>
    switch (result) {
      ExitPlanApprovalFailed(:final reason) => AiInteractiveFailed(reason),
      ExitPlanApprovalOk() => const AiInteractiveOk(),
    };
