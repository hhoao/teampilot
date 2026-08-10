import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../utils/ui/app_keys.dart';
import 'unbound_compose_body.dart';

export 'unbound_compose_body.dart' show LandingComposeSubmit;

/// Landing page chrome around [UnboundComposeBody]: full-bleed surface,
/// centered scroll, project/worktree header (via body), and back button.
class WorkspaceChatLanding extends StatelessWidget {
  const WorkspaceChatLanding({
    required this.workspace,
    required this.onSubmit,
    this.isSubmitting = false,
    this.disabled = false,
    this.initialText,
    super.key,
  });

  final Workspace workspace;
  final LandingComposeSubmit onSubmit;
  final bool isSubmitting;
  final bool disabled;
  final String? initialText;

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
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: UnboundComposeBody(
                    workspace: workspace,
                    onSubmit: onSubmit,
                    isSubmitting: isSubmitting,
                    disabled: disabled,
                    initialText: initialText,
                    deferFieldMount: true,
                    showLocationHeader: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: spacing.md,
          left: backLeft,
          child: TpIconButton(
            key: AppKeys.workspaceChatLandingBackButton,
            icon: Icons.arrow_back,
            size: TpIconButton.chromeAlignedSize(context),
            tooltip: l10n.workspaceChatLandingBackToStart,
            backgroundColor: Colors.transparent,
            onTap: () {
              final workspaceId = workspace.workspaceId;
              context.read<ChatCubit>().dismissNewChat();
              context.read<WorkbenchCubit>().enterLanding(workspaceId);
            },
          ),
        ),
      ],
    );
  }
}
