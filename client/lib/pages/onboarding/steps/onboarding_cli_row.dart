import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/cli/registry/cli_tool_definition.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/app_keys.dart';
import '../../../widgets/cli/cli_brand_icon.dart';

/// One launchable CLI row in the onboarding detect step.
class OnboardingCliRow extends StatelessWidget {
  const OnboardingCliRow({
    super.key,
    required this.definition,
    required this.label,
    required this.controller,
    required this.detectedPath,
    required this.detecting,
    required this.supportsInstall,
    required this.installing,
    required this.installEnabled,
    required this.onPathChanged,
    required this.onInstall,
  });

  final CliToolDefinition definition;
  final String label;
  final TextEditingController controller;
  final String? detectedPath;
  final bool detecting;
  final bool supportsInstall;
  final bool installing;
  final bool installEnabled;
  final ValueChanged<String> onPathChanged;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final cli = definition.id;
    final found = detectedPath != null && detectedPath!.isNotEmpty;
    final statusIcon = detecting
        ? SizedBox(
            width: context.appIconSizes.md,
            height: context.appIconSizes.md,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            found ? Icons.check_circle_outline : Icons.info_outline,
            size: context.appIconSizes.md,
            color: found ? cs.primary : cs.onSurfaceVariant,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CliBrandIcon(
            cli: cli,
            definition: definition,
            label: label,
            size: 28,
            borderRadius: 7,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.of(context).md,
            ),
          ),
          const SizedBox(width: 8),
          statusIcon,
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: AppKeys.cliExecutablePathFieldFor(cli),
              controller: controller,
              decoration: InputDecoration(
                isDense: true,
                hintText: found ? null : l10n.onboardingCliNotFound,
                hintMaxLines: 1,
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
              onChanged: onPathChanged,
            ),
          ),
          if (supportsInstall) ...[
            const SizedBox(width: 4),
            IconButton(
              key: AppKeys.cliInstallButtonFor(cli),
              tooltip: l10n.cliInstallButton,
              onPressed: installEnabled && !installing ? onInstall : null,
              icon: installing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.download_outlined,
                      size: context.appIconSizes.md,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
