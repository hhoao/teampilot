import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../strings.dart';

/// Interactive permission card — Allow once / Always allow / Reject, answered
/// in chat via host [onReply] (`once` / `always` / `reject`).
class AiPermissionCard extends StatefulWidget {
  const AiPermissionCard({
    required this.description,
    required this.onReply,
    required this.onAnswerInTerminal,
    this.showAlwaysAllow = false,
    this.externalError,
    super.key,
  });

  static const cardKey = Key('opencode-permission-card');
  static const allowOnceButtonKey = Key(
    'opencode-permission-allow-once-button',
  );
  static const alwaysButtonKey = Key('opencode-permission-always-button');
  static const rejectButtonKey = Key('opencode-permission-reject-button');
  static const inlineErrorKey = Key('opencode-permission-inline-error');

  final String description;
  final bool showAlwaysAllow;
  final Future<AiInteractiveResult> Function(String reply) onReply;
  final VoidCallback onAnswerInTerminal;

  /// Host-side error (e.g. attention cubit `askReplyError`), shown when the
  /// card has no inline submit failure.
  final String? externalError;

  @override
  State<AiPermissionCard> createState() => _AiPermissionCardState();
}

class _AiPermissionCardState extends State<AiPermissionCard> {
  var _answering = false;
  String? _inlineError;

  Future<void> _reply(String reply) async {
    if (_answering) return;
    setState(() {
      _answering = true;
      _inlineError = null;
    });
    final strings = AiMessageStrings.of(context);
    final AiInteractiveResult result;
    try {
      result = await widget.onReply(reply);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _answering = false;
        _inlineError = strings.permissionAnswerFailed;
      });
      return;
    }
    if (!mounted) return;
    if (result is AiInteractiveFailed) {
      setState(() {
        _answering = false;
        _inlineError = strings.permissionAnswerFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final strings = AiMessageStrings.of(context);
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    final displayError =
        _inlineError ??
        (widget.externalError == null ? null : strings.permissionAnswerFailed);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AiPermissionCard.cardKey,
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
                      strings.permissionTitle,
                      style: styles.smColored(cs.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  TpIconButton(
                    icon: Icons.terminal_rounded,
                    tooltip: strings.permissionAnswerInTerminal,
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
                widget.description,
                style: styles.mdColored(cs.onSurface).copyWith(height: 1.45),
              ),
              if (displayError != null) ...[
                SizedBox(height: spacing.md),
                Text(
                  displayError,
                  key: AiPermissionCard.inlineErrorKey,
                  style: styles.mdColored(cs.error),
                ),
              ],
              SizedBox(height: spacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TpButton(
                    key: AiPermissionCard.rejectButtonKey,
                    variant: TpButtonVariant.ghost,
                    size: TpControlSize.medium,
                    onPressed: _answering ? null : () => _reply('reject'),
                    child: Text(strings.permissionReject),
                  ),
                  if (widget.showAlwaysAllow) ...[
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: AiPermissionCard.alwaysButtonKey,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.medium,
                      onPressed: _answering ? null : () => _reply('always'),
                      child: Text(strings.permissionAllowAlways),
                    ),
                  ],
                  SizedBox(width: spacing.sm),
                  TpButton(
                    key: AiPermissionCard.allowOnceButtonKey,
                    variant: TpButtonVariant.primary,
                    size: TpControlSize.medium,
                    onPressed: _answering ? null : () => _reply('once'),
                    child: Text(strings.permissionAllowOnce),
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
