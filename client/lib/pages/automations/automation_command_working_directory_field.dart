import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../services/storage/home_storage.dart';
import '../home_workspace/workspace/workspace_landing_selectors.dart';
import 'package:shared_ui/shared_ui.dart';

/// Working-directory picker for `runCommand` automations.
///
/// Reuses the launch-prompt folder picker over [Workspace.folders]. The empty
/// value means "workspace main folder", which the runner resolves to the
/// first folder at execution time.
class AutomationCommandWorkingDirectoryField extends StatelessWidget {
  const AutomationCommandWorkingDirectoryField({
    required this.workspace,
    required this.workingDirectoryPath,
    required this.labelWidth,
    required this.onChanged,
    super.key,
  });

  final Workspace workspace;
  final String? workingDirectoryPath;
  final double labelWidth;
  final ValueChanged<String?> onChanged;

  bool _usesPosixPaths(BuildContext context) {
    try {
      return context.read<HomeStorage>().usesPosixPaths;
    } on ProviderNotFoundException {
      return !Platform.isWindows;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = workingDirectoryPath?.trim() ?? '';
    final resolver = WorkspaceLandingProjectResolver(
      workspace: workspace,
      usesPosixPaths: _usesPosixPaths(context),
      storedProjectPath: selected.isEmpty ? null : selected,
    );
    final mainLabel = l10n.automationsCommandWorkingDirectoryMain;
    final label = selected.isEmpty ? mainLabel : resolver.labelFor(selected);

    return TpFormField<String>(
      key: ValueKey('commandWorkingDirectory-$selected'),
      id: 'commandWorkingDirectory',
      initialValue: selected,
      label: Text(l10n.automationsCommandWorkingDirectory),
      layoutStyle: TpFormFieldLayoutStyle.inline,
      labelWidth: labelWidth,
      builder: (state) {
        return WorkspaceLandingSelectorBar(
          label: label,
          hintWhenEmpty: mainLabel,
          compact: true,
          menuSpecs: [
            TpActionMenuSpec.item(
              value: '',
              icon: Icons.folder_outlined,
              label: mainLabel,
              selected: selected.isEmpty,
            ),
            ...resolver.menuSpecs(selected),
          ],
          onSelected: (value) {
            if (value is! String) return;
            state.didChange(value);
            onChanged(value.trim().isEmpty ? null : value);
          },
        );
      },
    );
  }
}
