import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../utils/ui/app_keys.dart';
import 'unbound_compose_body.dart';

export 'unbound_compose_body.dart' show LandingComposeSubmit;

/// Centered width of the landing header row + compose card. Shared with
/// [WorkspaceLandingSkeleton] so the placeholder never shifts on mount.
const double kWorkspaceLandingMaxWidth = 1040;

/// Landing page chrome around [UnboundComposeBody]: full-bleed surface,
/// centered scroll, project/worktree header (via body), and back button.
///
/// Pure chrome: workbench state is resolved by the hosting pane, which passes
/// [showBackButton] / [onBack]. The landing doubles as the workspace start
/// page, so the back control only exists when the host says there is a
/// workbench context to return to.
class WorkspaceChatLanding extends StatelessWidget {
  const WorkspaceChatLanding({
    required this.workspace,
    required this.onSubmit,
    this.isSubmitting = false,
    this.disabled = false,
    this.initialText,
    this.initialTextRevision = 0,
    this.referencedSessionId,
    this.showBackButton = false,
    this.onBack,
    super.key,
  });

  final Workspace workspace;
  final LandingComposeSubmit onSubmit;
  final bool isSubmitting;
  final bool disabled;
  final String? initialText;
  final int initialTextRevision;
  final String? referencedSessionId;

  /// Whether the back control is mounted — true only when the landing was
  /// entered over an open workbench tab that can be restored.
  final bool showBackButton;

  /// Invoked on back; the host exits the workbench landing.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final isMobile =
        TpSidebarScope.maybeOf(context)?.isMobile ??
        MediaQuery.sizeOf(context).width < TpMobileChrome.narrowBreakpointWidth;
    final backLeft = isMobile
        ? math.max(spacing.md, TpMobileChrome.leadingInset)
        : spacing.md;

    return Stack(
      children: [
        ColoredBox(
          color: cs.surface,
          child: SizedBox.expand(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.xl,
                  vertical: spacing.xxl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kWorkspaceLandingMaxWidth,
                  ),
                  child: UnboundComposeBody(
                    workspace: workspace,
                    onSubmit: onSubmit,
                    isSubmitting: isSubmitting,
                    disabled: disabled,
                    initialText: initialText,
                    initialTextRevision: initialTextRevision,
                    referencedSessionId: referencedSessionId,
                    deferFieldMount: true,
                    showLocationHeader: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showBackButton)
          Positioned(
            top: spacing.md,
            left: backLeft,
            child: TpIconButton(
              key: AppKeys.workspaceChatLandingBackButton,
              icon: Icons.arrow_back,
              size: TpIconButton.chromeAlignedSize(context),
              tooltip: l10n.workspaceChatLandingBackToWorkbench,
              backgroundColor: Colors.transparent,
              onTap: onBack,
            ),
          ),
      ],
    );
  }
}
