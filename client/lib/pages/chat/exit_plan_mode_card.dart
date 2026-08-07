import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/exit_plan_mode_approval_service.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/ui/app_keys.dart';

/// Chat card for Claude `ExitPlanMode`: Markdown plan, expand/collapse, copy,
/// clickable plan file, and (when [onApprove]/[onReject] are provided) an
/// in-chat Approve / Reject footer.
class ExitPlanModeCard extends StatefulWidget {
  const ExitPlanModeCard({
    required this.planText,
    this.planFilePath,
    this.onApprove,
    this.onReject,
    required this.onOpenTerminal,
    required this.onOpenPlanFile,
    super.key,
  });

  final String planText;
  final String? planFilePath;

  /// When both are non-null, the card renders in-chat Approve / Reject.
  final Future<ExitPlanApprovalResult> Function()? onApprove;
  final Future<ExitPlanApprovalResult> Function()? onReject;
  final VoidCallback onOpenTerminal;
  final ValueChanged<String> onOpenPlanFile;

  @override
  State<ExitPlanModeCard> createState() => _ExitPlanModeCardState();
}

class _ExitPlanModeCardState extends State<ExitPlanModeCard> {
  var _expanded = false;
  var _approving = false;
  String? _inlineError;

  bool get _canApprove => widget.onApprove != null && widget.onReject != null;

  Future<void> _approve() => _submit(widget.onApprove, approve: true);

  Future<void> _reject() => _submit(widget.onReject, approve: false);

  Future<void> _submit(
    Future<ExitPlanApprovalResult> Function()? action, {
    required bool approve,
  }) async {
    if (action == null || _approving) return;
    setState(() {
      _approving = true;
      _inlineError = null;
    });
    final ExitPlanApprovalResult result;
    try {
      result = await action();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _approving = false;
        _inlineError = approve
            ? context.l10n.exitPlanModeApproveFailed
            : context.l10n.exitPlanModeRejectFailed;
      });
      return;
    }
    if (!mounted) return;
    if (result is ExitPlanApprovalFailed) {
      setState(() {
        _approving = false;
        _inlineError = approve
            ? context.l10n.exitPlanModeApproveFailed
            : context.l10n.exitPlanModeRejectFailed;
      });
    } else {
      setState(() => _approving = false);
    }
  }

  Future<void> _copyPlan() async {
    await Clipboard.setData(ClipboardData(text: widget.planText));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final path = widget.planFilePath?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AppKeys.exitPlanModeCard,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.fact_check_rounded, size: 16, color: cs.tertiary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.exitPlanModeTitle,
                      style: styles.smColored(cs.onSurface),
                    ),
                  ),
                  TpIconButton(
                    key: AppKeys.exitPlanModeCopyPlanButton,
                    icon: Icons.copy_rounded,
                    tooltip: l10n.exitPlanModeCopyPlan,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    borderRadius: radius,
                    onTap: widget.planText.isEmpty ? null : _copyPlan,
                  ),
                ],
              ),
              if (widget.planText.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: Container(
                    constraints: _expanded
                        ? null
                        : const BoxConstraints(maxHeight: 160),
                    padding: EdgeInsets.all(spacing.sm),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    child: SingleChildScrollView(
                      child: MarkdownView(
                        document: compileMarkdown(widget.planText),
                        tokens: buildAppMarkdownTokens(
                          Theme.of(context),
                          MarkdownProfile.compact,
                          width: MediaQuery.sizeOf(context).width,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: AppKeys.exitPlanModeExpandButton,
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded
                          ? l10n.exitPlanModeCollapse
                          : l10n.exitPlanModeExpand,
                    ),
                  ),
                ),
              ],
              if (path.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                Tooltip(
                  key: AppKeys.exitPlanModeOpenPlanFileButton,
                  message: l10n.exitPlanModeOpenPlanFile,
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
                              style: styles.xsColored(cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (_inlineError != null) ...[
                SizedBox(height: spacing.sm),
                Text(
                  _inlineError!,
                  key: AppKeys.exitPlanModeInlineError,
                  style: styles.smColored(cs.error),
                ),
              ],
              SizedBox(height: spacing.sm),
              if (_canApprove) ...[
                Row(
                  children: [
                    TpIconButton(
                      key: AppKeys.agentPermissionOpenTerminalButton,
                      icon: Icons.terminal_rounded,
                      tooltip: l10n.agentPermissionOpenTerminal,
                      compact: true,
                      size: TpIconButton.kCompactSize,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      borderRadius: radius,
                      onTap: widget.onOpenTerminal,
                    ),
                    const Spacer(),
                    TpButton(
                      key: AppKeys.exitPlanModeRejectButton,
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.small,
                      onPressed: _approving ? null : _reject,
                      child: Text(l10n.exitPlanModeReject),
                    ),
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: AppKeys.exitPlanModeApproveButton,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.small,
                      onPressed: _approving ? null : _approve,
                      child: Text(l10n.exitPlanModeApprove),
                    ),
                  ],
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TpButton(
                    key: AppKeys.agentPermissionOpenTerminalButton,
                    variant: TpButtonVariant.primary,
                    size: TpControlSize.small,
                    onPressed: widget.onOpenTerminal,
                    child: Text(l10n.agentPermissionOpenTerminal),
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
