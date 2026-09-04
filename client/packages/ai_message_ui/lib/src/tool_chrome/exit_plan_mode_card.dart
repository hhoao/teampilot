import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../strings.dart';
import '../theme.dart';

/// Chat card for Claude `ExitPlanMode`: compact summary row with a floating
/// plan preview, clickable plan file, and (when [onApprove]/[onReject] are
/// provided) an in-chat Approve / Reject footer.
///
/// The plan itself renders in a modal preview ([showTpDialog]) opened via the
/// view-plan affordance — the card stays as small as the other interactive
/// cards.
class AiExitPlanModeCard extends StatefulWidget {
  const AiExitPlanModeCard({
    required this.planText,
    this.planFilePath,
    this.onApprove,
    this.onReject,
    required this.onOpenTerminal,
    required this.onOpenPlanFile,
    super.key,
  });

  static const cardKey = Key('exit-plan-mode-card');
  static const approveButtonKey = Key('exit-plan-mode-approve-button');
  static const rejectButtonKey = Key('exit-plan-mode-reject-button');
  static const copyPlanButtonKey = Key('exit-plan-mode-copy-plan-button');
  static const viewPlanButtonKey = Key('exit-plan-mode-view-plan-button');
  static const previewDialogKey = Key('exit-plan-mode-preview-dialog');
  static const openPlanFileButtonKey = Key(
    'exit-plan-mode-open-plan-file-button',
  );
  static const inlineErrorKey = Key('exit-plan-mode-inline-error');
  static const openTerminalButtonKey = Key(
    'agent-permission-open-terminal-button',
  );

  final String planText;
  final String? planFilePath;

  /// When both are non-null, the card renders in-chat Approve / Reject.
  final Future<AiInteractiveResult> Function()? onApprove;
  final Future<AiInteractiveResult> Function()? onReject;
  final VoidCallback onOpenTerminal;
  final ValueChanged<String> onOpenPlanFile;

  @override
  State<AiExitPlanModeCard> createState() => _AiExitPlanModeCardState();
}

class _AiExitPlanModeCardState extends State<AiExitPlanModeCard> {
  var _approving = false;
  String? _inlineError;

  bool get _canApprove => widget.onApprove != null && widget.onReject != null;

  Future<void> _approve() => _submit(widget.onApprove, approve: true);

  Future<void> _reject() => _submit(widget.onReject, approve: false);

  Future<void> _submit(
    Future<AiInteractiveResult> Function()? action, {
    required bool approve,
  }) async {
    if (action == null || _approving) return;
    setState(() {
      _approving = true;
      _inlineError = null;
    });
    final strings = AiMessageStrings.of(context);
    final AiInteractiveResult result;
    try {
      result = await action();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _approving = false;
        _inlineError = approve
            ? strings.exitPlanApproveFailed
            : strings.exitPlanRejectFailed;
      });
      return;
    }
    if (!mounted) return;
    if (result is AiInteractiveFailed) {
      setState(() {
        _approving = false;
        _inlineError = approve
            ? strings.exitPlanApproveFailed
            : strings.exitPlanRejectFailed;
      });
    } else {
      setState(() => _approving = false);
    }
  }

  Future<void> _copyPlan() async {
    await Clipboard.setData(ClipboardData(text: widget.planText));
  }

  Future<void> _openPreview() async {
    final strings = AiMessageStrings.of(context);
    final path = widget.planFilePath?.trim() ?? '';
    await showTpDialog(
      context: context,
      builder: (dialogContext) => TpDialog(
        key: AiExitPlanModeCard.previewDialogKey,
        maxWidth: 720,
        maxHeight: 640,
        child: TpDialogPinnedLayout(
          header: TpDialogHeader(
            title: strings.exitPlanPreviewTitle,
            trailing: TpIconButton(
              key: AiExitPlanModeCard.copyPlanButtonKey,
              icon: Icons.copy_rounded,
              tooltip: strings.exitPlanCopy,
              compact: true,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              onTap: _copyPlan,
            ),
          ),
          body: MarkdownView(
            document: compileMarkdown(widget.planText),
            tokens: AiMessageTheme.of(dialogContext).markdown,
          ),
          footer: path.isEmpty
              ? null
              : TpDialogActions(
                  children: [
                    TpButton(
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.medium,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        widget.onOpenPlanFile(path);
                      },
                      child: Text(strings.exitPlanOpenFile),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final strings = AiMessageStrings.of(context);
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final path = widget.planFilePath?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AiExitPlanModeCard.cardKey,
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
                  Icon(Icons.fact_check_rounded, size: 18, color: cs.tertiary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      strings.exitPlanTitle,
                      style: styles.smColored(cs.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  TpIconButton(
                    icon: Icons.terminal_rounded,
                    tooltip: strings.permissionOpenTerminal,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    borderRadius: radius,
                    enabled: !_approving,
                    onTap: widget.onOpenTerminal,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              Row(
                children: [
                  if (widget.planText.isNotEmpty)
                    TpButton(
                      key: AiExitPlanModeCard.viewPlanButtonKey,
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.small,
                      onPressed: _openPreview,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          SizedBox(width: spacing.xs),
                          Text(strings.exitPlanViewPlan),
                        ],
                      ),
                    ),
                  if (widget.planText.isNotEmpty && path.isNotEmpty)
                    SizedBox(width: spacing.sm),
                  if (path.isNotEmpty)
                    Expanded(
                      child: Tooltip(
                        key: AiExitPlanModeCard.openPlanFileButtonKey,
                        message: strings.exitPlanOpenFile,
                        child: TpHover(
                          borderRadius: BorderRadius.circular(radius),
                          onTap: () => widget.onOpenPlanFile(path),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.xs,
                              vertical: spacing.xs,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                SizedBox(width: spacing.xs),
                                Expanded(
                                  child: Text(
                                    path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: styles.xsColored(
                                      cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_inlineError != null) ...[
                SizedBox(height: spacing.md),
                Text(
                  _inlineError!,
                  key: AiExitPlanModeCard.inlineErrorKey,
                  style: styles.mdColored(cs.error),
                ),
              ],
              SizedBox(height: spacing.md),
              if (_canApprove) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TpButton(
                      key: AiExitPlanModeCard.rejectButtonKey,
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.medium,
                      onPressed: _approving ? null : _reject,
                      child: Text(strings.exitPlanReject),
                    ),
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: AiExitPlanModeCard.approveButtonKey,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.medium,
                      onPressed: _approving ? null : _approve,
                      child: Text(strings.exitPlanApprove),
                    ),
                  ],
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TpButton(
                    key: AiExitPlanModeCard.openTerminalButtonKey,
                    variant: TpButtonVariant.primary,
                    size: TpControlSize.medium,
                    onPressed: widget.onOpenTerminal,
                    child: Text(strings.permissionOpenTerminal),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
