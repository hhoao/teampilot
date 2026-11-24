import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../widgets/app_provider/cli_effort_picker_field.dart';
import '../qoder_flavor.dart';

/// Qoder-only provider fields: reasoning effort.
///
/// The context window moved to the per-model editor
/// (`provider_models_editor.dart`).
class QoderProviderFormSection extends StatelessWidget {
  const QoderProviderFormSection({
    required this.flavor,
    required this.effort,
    required this.defaultModel,
    required this.onEffortChanged,
    super.key,
  });

  final QoderFlavor flavor;
  final String effort;
  final String defaultModel;
  final ValueChanged<String> onEffortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          l10n.appProvider.advancedOptions,
          style: styles.mdSemiboldTightSnug,
        ),
        children: [
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.provider.effortLevel, style: styles.mdSnug),
          ),
          const SizedBox(height: 6),
          CliEffortPickerField(
            cli: flavor.cli,
            value: effort,
            model: defaultModel,
            provider: AppProviderConfig(
              id: '${flavor.cli.value}-form',
              cli: flavor.cli,
              name: flavor.providerLabel,
              defaultModel: defaultModel,
            ),
            onChanged: onEffortChanged,
          ),
        ],
      ),
    );
  }
}
