import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';

import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/acp/acp_client_extensions.dart';
import 'ai_message_strings_from_l10n.dart';

/// Interactive plan-approval card for a terminal-less ACP chat session.
///
/// Renders held plan text through the shared [AiExitPlanModeCard] chrome.
/// Approve and reject route to [AcpChatRuntimeCubit.answerPlan]; the header's
/// terminal action cancels the turn ([AcpChatRuntimeCubit.cancelTurn]) — ACP
/// has no terminal to jump to. There is no on-disk plan file for Cursor ACP
/// `create_plan`, so [AiExitPlanModeCard.onOpenPlanFile] is a no-op.
///
/// Rendered by [SessionChatComposeSection] in the same slot as
/// [AcpPermissionCard] / [AgentPermissionAttentionBanner].
class AcpPlanCard extends StatelessWidget {
  const AcpPlanCard({required this.runtime, required this.planText, super.key});

  /// The session's ACP runtime; receives the replies.
  final AcpChatRuntimeCubit runtime;

  /// Plan markdown from the held [AcpPendingPlan].
  final String planText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AiMessageStringsScope(
      strings: aiMessageStringsFromL10n(l10n),
      child: AiExitPlanModeCard(
        planText: planText,
        onApprove: () async {
          await runtime.answerPlan(const AcpPlanHoldReply.accepted());
          return const AiInteractiveOk();
        },
        onReject: () async {
          await runtime.answerPlan(const AcpPlanHoldReply.rejected());
          return const AiInteractiveOk();
        },
        onOpenTerminal: runtime.cancelTurn,
        onOpenPlanFile: (_) {},
      ),
    );
  }
}
