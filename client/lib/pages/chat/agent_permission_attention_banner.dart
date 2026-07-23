import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../services/agent_status/agent_attention_state.dart';
import '../../utils/ui/app_keys.dart';

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

  @override
  Widget build(BuildContext context) {
    final sessionId = session.sessionId;
    final workbenchView = context.select<ChatCubit, SessionWorkbenchView>((c) {
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
    final waiting = context.select<AgentAttentionCubit, bool>((c) {
      return c.state.attentionFor(sessionId: sessionId, memberId: seatId) ==
          AgentSeatAttention.waiting;
    });
    if (!waiting) return const SizedBox.shrink();

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
