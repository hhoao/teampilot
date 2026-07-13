import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_type_contribution.dart';
import '../../services/run/launch_config_l10n.dart';
import '../../services/run/shell_script_launch_schema.dart';
import '../../theme/app_text_styles.dart';
import '../app_dialog.dart';

/// Opens an IDEA-style launch-type picker. Returns the selected type id, or
/// null when dismissed.
Future<String?> showRunConfigTypePickerDialog(
  BuildContext context, {
  required List<LaunchTypeContribution> types,
  bool Function(LaunchTypeContribution type)? isAvailable,
  String? Function(LaunchTypeContribution type)? unavailableReason,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => RunConfigTypePickerDialog(
      types: types,
      isAvailable: isAvailable,
      unavailableReason: unavailableReason,
    ),
  );
}

/// Lists built-in Shell Script first, then extension launch types.
class RunConfigTypePickerDialog extends StatelessWidget {
  const RunConfigTypePickerDialog({
    required this.types,
    this.isAvailable,
    this.unavailableReason,
    super.key,
  });

  final List<LaunchTypeContribution> types;
  final bool Function(LaunchTypeContribution type)? isAvailable;
  final String? Function(LaunchTypeContribution type)? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final ordered = _orderedTypes(types);

    return AppDialog(
      maxWidth: 420,
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: l10n.runPickLaunchType,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          if (ordered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.runTypeUnknown(''),
                style: styles.mdColored(cs.onSurfaceVariant),
              ),
            )
          else
            for (final type in ordered)
              _TypeRow(
                contribution: type,
                enabled: isAvailable?.call(type) ?? true,
                reason: unavailableReason?.call(type),
              ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.contribution,
    required this.enabled,
    this.reason,
  });

  final LaunchTypeContribution contribution;
  final bool enabled;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final label = localizeLaunchTypeLabel(l10n, contribution.type);
    final subtitle = reason?.trim();

    return ListTile(
      key: Key('run-config-type-${contribution.type}'),
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        contribution.type == ShellScriptLaunchSchema.typeName
            ? Icons.terminal_outlined
            : Icons.extension_outlined,
        color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.38),
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: enabled
            ? styles.md
            : styles.mdColored(cs.onSurface.withValues(alpha: 0.38)),
      ),
      subtitle: subtitle != null && subtitle.isNotEmpty
          ? Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: styles.xsColored(cs.onSurfaceVariant),
            )
          : null,
      onTap: enabled
          ? () => Navigator.of(context).pop(contribution.type)
          : null,
    );
  }
}

List<LaunchTypeContribution> _orderedTypes(
  List<LaunchTypeContribution> types,
) {
  final builtIn = <LaunchTypeContribution>[];
  final extensions = <LaunchTypeContribution>[];
  for (final type in types) {
    if (type.type == ShellScriptLaunchSchema.typeName) {
      builtIn.add(type);
    } else if (type.type == ShellScriptLaunchSchema.processAlias) {
      // Never surface legacy `process` in the picker.
      continue;
    } else {
      extensions.add(type);
    }
  }
  extensions.sort((a, b) => a.type.compareTo(b.type));
  return [...builtIn, ...extensions];
}
