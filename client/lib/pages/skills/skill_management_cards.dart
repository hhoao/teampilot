import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class SkillManagementCard extends StatelessWidget {
  const SkillManagementCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}

class SkillCardHeader extends StatelessWidget {
  const SkillCardHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ManagementCardHeader(title: title, trailing: trailing);
  }
}

class SkillFieldLabel extends StatelessWidget {
  const SkillFieldLabel({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    return Text(
      text,
      style: AppTextStyles.of(context).bodySmall.copyWith(
        fontWeight: FontWeight.w600,
        color: textBase.withValues(alpha: 0.7),
      ),
    );
  }
}

Future<bool> skillConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: title,
            onClose: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: 16),
          Text(message),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(ctx).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

void showSkillSnack(
  BuildContext context,
  String message, {
  AppToastVariant variant = AppToastVariant.info,
}) {
  AppToast.show(context, message: message, variant: variant);
}
