import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class PluginManagementCard extends StatelessWidget {
  const PluginManagementCard({super.key, required this.child});
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

class PluginCardHeader extends StatelessWidget {
  const PluginCardHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ManagementCardHeader(title: title, trailing: trailing);
  }
}

Future<bool> pluginConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  List<String>? detailLines,
  String? detailHeading,
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
          AppDialogHeader(title: title),
          const SizedBox(height: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (detailLines != null && detailLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (detailHeading != null)
                  Text(
                    detailHeading,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                for (final line in detailLines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $line'),
                  ),
              ],
            ],
          ),
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

void showPluginSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

Future<void> openPluginUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class PluginEmptyBlock extends StatelessWidget {
  const PluginEmptyBlock({
    required this.icon,
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      children: [
        const SizedBox(height: 10),
        Icon(icon, size: context.appIconSizes.md, color: cs.primary.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(
          title,
          style: AppTextStyles.of(
            context,
          ).subtitle.copyWith(fontWeight: FontWeight.w700, color: textBase),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: AppTextStyles.of(
            context,
          ).body.copyWith(color: textBase.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        const SizedBox(height: 10),
      ],
    );
  }
}

