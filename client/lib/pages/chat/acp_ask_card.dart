import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';

import '../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/acp/acp_client_extensions.dart';
import 'ai_message_strings_from_l10n.dart';

/// Interactive ask-user card for a terminal-less ACP chat session.
///
/// Renders held [AiAskUserQuestion]s through the shared
/// [AiAskUserQuestionCard] chrome. Submit and ignore route to
/// [AcpChatRuntimeCubit.answerAsk]; the header's terminal action cancels the
/// turn ([AcpChatRuntimeCubit.cancelTurn]) — ACP has no terminal to jump to.
///
/// Rendered by [SessionChatComposeSection] in the same slot as
/// [AcpPermissionCard] / [AgentPermissionAttentionBanner].
class AcpAskCard extends StatelessWidget {
  const AcpAskCard({required this.runtime, required this.questions, super.key});

  /// The session's ACP runtime; receives the replies.
  final AcpChatRuntimeCubit runtime;

  /// Questions from the held [AcpPendingAsk].
  final List<AiAskUserQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AiMessageStringsScope(
      strings: aiMessageStringsFromL10n(l10n),
      child: AiAskUserQuestionCard(
        questions: questions,
        onSubmit: (submission) async {
          await runtime.answerAsk(AcpAskHoldReply.answered(submission));
          return const AiInteractiveOk();
        },
        onCancel: () async {
          await runtime.answerAsk(const AcpAskHoldReply.skipped());
          return const AiInteractiveOk();
        },
        onAnswerInTerminal: runtime.cancelTurn,
      ),
    );
  }
}
