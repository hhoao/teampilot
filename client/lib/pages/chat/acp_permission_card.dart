import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';

import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/agent_status/agent_permission_request.dart';
import 'ai_message_strings_from_l10n.dart';

/// Interactive permission card for a terminal-less ACP chat session
/// (gemini phase 1).
///
/// Renders [AcpChatRuntimeCubit.state.pendingPermission] through the shared
/// [AiPermissionCard] chrome: the agent's request description, its
/// always-allow options, and allow-once / always / reject replies routed to
/// [AcpChatRuntimeCubit.answerPermission]. The header's cancel action cancels
/// the whole turn ([AcpChatRuntimeCubit.cancelTurn]) — the ACP analogue of
/// dismissing the prompt and stopping the agent.
///
/// Rendered by [SessionChatComposeSection] in the same slot as
/// [AgentPermissionAttentionBanner] (above the compose card). ACP sessions
/// have no terminal to switch to, so [AiPermissionCard.onAnswerInTerminal]
/// cancels the turn instead of jumping views.
class AcpPermissionCard extends StatelessWidget {
  const AcpPermissionCard({
    required this.runtime,
    required this.pendingPermission,
    super.key,
  });

  /// The session's ACP runtime; receives the replies.
  final AcpChatRuntimeCubit runtime;

  /// The held permission request (the card's data source).
  final AgentPermissionRequest pendingPermission;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final alwaysOptions = [
      for (final option in pendingPermission.always)
        option.payload == null
            ? l10n.opencodePermissionAllowAlways
            : l10n.agentPermissionAlwaysAllowRule(option.label),
    ];
    return AiMessageStringsScope(
      strings: aiMessageStringsFromL10n(l10n),
      child: AiPermissionCard(
        description: pendingPermission.description,
        alwaysOptions: alwaysOptions,
        onReply: (reply) async {
          final delivered = await runtime.answerPermission(
            switch (reply.kind) {
              AiPermissionReplyKind.allowOnce =>
                AgentPermissionReplyKind.allowOnce,
              AiPermissionReplyKind.always => AgentPermissionReplyKind.always,
              AiPermissionReplyKind.reject => AgentPermissionReplyKind.reject,
            },
            alwaysPayload: reply.alwaysOptionIndex == null
                ? null
                : pendingPermission.always[reply.alwaysOptionIndex!].payload,
          );
          return delivered
              ? const AiInteractiveOk()
              : AiInteractiveFailed(l10n.opencodePermissionAnswerFailed);
        },
        onAnswerInTerminal: runtime.cancelTurn,
      ),
    );
  }
}
