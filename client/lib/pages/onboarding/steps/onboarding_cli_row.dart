import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/cli/registry/cli_tool_definition.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../widgets/cli/cli_brand_icon.dart';

/// One launchable CLI row in the onboarding detect step.
class OnboardingCliRow extends StatelessWidget {
  const OnboardingCliRow({
    super.key,
    required this.definition,
    required this.label,
    required this.controller,
    required this.detectedPath,
    required this.supportsInstall,
    required this.installing,
    required this.busyListenable,
    required this.onPathChanged,
    required this.onInstall,
  });

  final CliToolDefinition definition;
  final String label;
  final TextEditingController controller;
  final String? detectedPath;
  final bool supportsInstall;
  final bool installing;
  final ValueListenable<bool> busyListenable;
  final ValueChanged<String> onPathChanged;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final cli = definition.id;
    final found = detectedPath != null && detectedPath!.isNotEmpty;

    Widget brandIcon() {
      // Stable key keeps SVG brand marks from reloading on parent rebuilds.
      return CliBrandIcon(
        key: ValueKey('onboarding-cli-icon-${cli.value}'),
        cli: cli,
        definition: definition,
        label: label,
        size: 28,
        borderRadius: 7,
      );
    }

    Widget labelText({required bool expanded}) {
      final text = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TpTextStyles.of(context).md,
      );
      if (expanded) {
        return Expanded(child: text);
      }
      return SizedBox(width: 110, child: text);
    }

    Widget statusIcon() {
      return Icon(
        found ? Icons.check_circle_outline : Icons.info_outline,
        size: context.tpIconSizes.md,
        color: found ? cs.primary : cs.onSurfaceVariant,
      );
    }

    Widget pathField() {
      return TextField(
        key: AppKeys.cliExecutablePathFieldFor(cli),
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          hintText: found ? null : l10n.onboardingCliNotFound,
          hintMaxLines: 1,
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
        onChanged: onPathChanged,
      );
    }

    Widget? installButton() {
      if (!supportsInstall) return null;
      return ValueListenableBuilder<bool>(
        valueListenable: busyListenable,
        builder: (context, busy, _) {
          return IconButton(
            key: AppKeys.cliInstallButtonFor(cli),
            tooltip: l10n.cliInstallButton,
            onPressed: busy || installing ? null : onInstall,
            icon: installing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.download_outlined,
                    size: context.tpIconSizes.md,
                  ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final install = installButton();
          if (TpBreakpoints.down(constraints.maxWidth, TpBreakpoint.sm)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    brandIcon(),
                    const SizedBox(width: 10),
                    labelText(expanded: true),
                    const SizedBox(width: 8),
                    statusIcon(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: pathField()),
                    if (install != null) ...[
                      const SizedBox(width: 4),
                      install,
                    ],
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              brandIcon(),
              const SizedBox(width: 10),
              labelText(expanded: false),
              const SizedBox(width: 8),
              statusIcon(),
              const SizedBox(width: 8),
              Expanded(child: pathField()),
              if (install != null) ...[
                const SizedBox(width: 4),
                install,
              ],
            ],
          );
        },
      ),
    );
  }
}
