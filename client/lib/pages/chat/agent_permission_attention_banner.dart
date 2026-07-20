import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat/model/session_workbench_view.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../services/agent_status/agent_attention_state.dart';
import '../../utils/ui/app_keys.dart';

/// History strip when the selected seat is waiting on a Terminal permission.
///
/// Does not auto-switch the workbench; the CTA jumps to Terminal (and selects
/// the waiting seat when it differs from the current selection).
class AgentPermissionAttentionBanner extends StatelessWidget {
  const AgentPermissionAttentionBanner({required this.session, super.key});

  final AppSession session;

  /// Seat id used for attention lookup (simple → [AppSession.sessionId]).
  static String attentionMemberId({
    required AppSession session,
    required String selectedMemberId,
  }) {
    if (session.isSimple) return session.sessionId;
    final mid = selectedMemberId.trim();
    return mid.isEmpty ? session.sessionId : mid;
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = session.sessionId;
    final workbenchView = context.select<ChatCubit, SessionWorkbenchView>((c) {
      final tab = c.tabStore.openTabBySessionId(sessionId);
      return tab?.workbenchView ?? SessionWorkbenchView.history;
    });
    if (workbenchView != SessionWorkbenchView.history) {
      return const SizedBox.shrink();
    }

    final selectedMemberId = context.select<ChatCubit, String>(
      (c) => c.state.selectedMemberId,
    );
    final seatId = attentionMemberId(
      session: session,
      selectedMemberId: selectedMemberId,
    );
    final waiting = context.select<AgentAttentionCubit, bool>((c) {
      return c.state.attentionFor(sessionId: sessionId, memberId: seatId) ==
          AgentSeatAttention.waiting;
    });
    if (!waiting) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Material(
      key: AppKeys.agentPermissionAttentionBanner,
      color: cs.tertiaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.tpSpacing.md,
          vertical: context.tpSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.agentPermissionAttentionBanner,
                style: TpTextStyles.of(
                  context,
                ).smColored(cs.onTertiaryContainer),
              ),
            ),
            SizedBox(width: context.tpSpacing.sm),
            TpButton(
              key: AppKeys.agentPermissionOpenTerminalButton,
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
}
