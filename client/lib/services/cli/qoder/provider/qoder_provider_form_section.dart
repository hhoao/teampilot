import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../widgets/app_provider/cli_effort_picker_field.dart';

/// Qoder-only provider fields: reasoning effort and context window.
class QoderProviderFormSection extends StatefulWidget {
  const QoderProviderFormSection({
    required this.effort,
    required this.contextWindow,
    required this.defaultModel,
    required this.onEffortChanged,
    required this.onContextWindowChanged,
    super.key,
  });

  final String effort;
  final String contextWindow;
  final String defaultModel;
  final ValueChanged<String> onEffortChanged;
  final ValueChanged<String> onContextWindowChanged;

  @override
  State<QoderProviderFormSection> createState() =>
      _QoderProviderFormSectionState();
}

class _QoderProviderFormSectionState extends State<QoderProviderFormSection> {
  late final TextEditingController _contextWindow = TextEditingController(
    text: widget.contextWindow,
  );

  @override
  void didUpdateWidget(QoderProviderFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.contextWindow != oldWidget.contextWindow &&
        _contextWindow.text != widget.contextWindow) {
      _contextWindow.text = widget.contextWindow;
    }
  }

  @override
  void dispose() {
    _contextWindow.dispose();
    super.dispose();
  }

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
          l10n.appProviderAdvancedOptions,
          style: styles.mdSemiboldTightSnug,
        ),
        children: [
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.providerEffortLevel, style: styles.mdSnug),
          ),
          const SizedBox(height: 6),
          CliEffortPickerField(
            cli: CliTool.qoder,
            value: widget.effort,
            model: widget.defaultModel,
            provider: AppProviderConfig(
              id: 'qoder-form',
              cli: CliTool.qoder,
              name: 'Qoder',
              defaultModel: widget.defaultModel,
            ),
            onChanged: widget.onEffortChanged,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.qoderContextWindow, style: styles.mdSnug),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _contextWindow,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: l10n.qoderContextWindowHint,
            ),
            onChanged: widget.onContextWindowChanged,
          ),
        ],
      ),
    );
  }
}
