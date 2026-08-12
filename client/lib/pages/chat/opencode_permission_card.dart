import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../services/agent_status/agent_permission_request.dart';
import '../../services/terminal/ask_user_question_answer_service.dart';
import '../../utils/ui/app_keys.dart';

/// Interactive OpenCode permission card — shows what the agent wants to run
/// with Allow once / Always allow / Reject actions answered in chat (delivered
/// by the agent-status plugin to `POST /permission/{id}/reply`).
class OpenCodePermissionCard extends StatefulWidget {
  const OpenCodePermissionCard({
    required this.session,
    required this.seatId,
    required this.request,
    required this.askRequestId,
    required this.onAnswerInTerminal,
    super.key,
  });

  final AppSession session;

  /// Shell / seat key (`sessionId` for simple, member id for team).
  final String seatId;
  final AgentPermissionRequest request;
  final String askRequestId;
  final VoidCallback onAnswerInTerminal;

  @override
  State<OpenCodePermissionCard> createState() => _OpenCodePermissionCardState();
}

class _OpenCodePermissionCardState extends State<OpenCodePermissionCard> {
  var _answering = false;
  String? _inlineError;

  Future<void> _reply(String reply) async {
    if (_answering) return;
    setState(() => _answering = true);
    final result = await context.read<ChatCubit>().answerPermissionRequest(
      sessionId: widget.session.sessionId,
      memberId: widget.seatId,
      permissionRequestId: widget.askRequestId,
      reply: reply,
    );
    if (!mounted) return;
    if (result is AskUserAnswerFailed) {
      setState(() {
        _answering = false;
        _inlineError = result.reason;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    final askReplyError = context.select<AgentAttentionCubit, String?>((c) {
      final entry = c.state.entryFor(
        sessionId: widget.session.sessionId,
        memberId: widget.seatId,
      );
      return entry?.askReplyError;
    });
    final displayError =
        _inlineError ?? (askReplyError == null ? null : l10n.opencodePermissionAnswerFailed);

    final showAlways = widget.request.always.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AppKeys.opencodePermissionCard,
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 4),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.lg,
            spacing.lg,
            spacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: cs.tertiary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.opencodePermissionTitle,
                      style: styles.smColored(cs.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  TpIconButton(
                    icon: Icons.terminal_rounded,
                    tooltip: l10n.opencodePermissionAnswerInTerminal,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    borderRadius: radius,
                    enabled: !_answering,
                    onTap: widget.onAnswerInTerminal,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              SelectableText(
                widget.request.description,
                style: styles.mdColored(cs.onSurface).copyWith(height: 1.45),
              ),
              if (displayError != null) ...[
                SizedBox(height: spacing.md),
                Text(
                  displayError,
                  key: AppKeys.opencodePermissionInlineError,
                  style: styles.mdColored(cs.error),
                ),
              ],
              SizedBox(height: spacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TpButton(
                    key: AppKeys.opencodePermissionRejectButton,
                    variant: TpButtonVariant.ghost,
                    size: TpControlSize.medium,
                    onPressed: _answering ? null : () => _reply('reject'),
                    child: Text(l10n.opencodePermissionReject),
                  ),
                  if (showAlways) ...[
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: AppKeys.opencodePermissionAlwaysButton,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.medium,
                      onPressed: _answering ? null : () => _reply('always'),
                      child: Text(l10n.opencodePermissionAllowAlways),
                    ),
                  ],
                  SizedBox(width: spacing.sm),
                  TpButton(
                    key: AppKeys.opencodePermissionAllowOnceButton,
                    variant: TpButtonVariant.primary,
                    size: TpControlSize.medium,
                    onPressed: _answering ? null : () => _reply('once'),
                    child: Text(l10n.opencodePermissionAllowOnce),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
