import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/extension_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class LayoutExtensionsSection extends StatefulWidget {
  const LayoutExtensionsSection();

  @override
  State<LayoutExtensionsSection> createState() => LayoutExtensionsSectionState();
}

class LayoutExtensionsSectionState extends State<LayoutExtensionsSection> {
  @override
  void initState() {
    super.initState();
    context.read<ExtensionCubit>().load();
  }

  String _statusText(BuildContext context, ExtensionRow row) {
    final l10n = context.l10n;
    switch (row.status) {
      case ExtensionStatusCode.notInstalled:
        return l10n.extensionStatusNotInstalled;
      case ExtensionStatusCode.dependencyMissing:
        return l10n.extensionStatusDependencyMissing;
      case ExtensionStatusCode.versionTooOld:
        return l10n.extensionStatusVersionTooOld;
      case ExtensionStatusCode.ready:
        final v = row.version?.trim();
        return (v == null || v.isEmpty)
            ? l10n.extensionStatusReady
            : l10n.extensionStatusReadyVersion(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<ExtensionCubit, ExtensionUiState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroupHeader(title: l10n.extensionsSettingsTitle),
            if (state.status == ExtensionLoadStatus.loading && state.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              for (var i = 0; i < state.rows.length; i++)
                _extensionRow(
                  context,
                  state,
                  state.rows[i],
                  last: i == state.rows.length - 1,
                ),
          ],
        );
      },
    );
  }

  Widget _extensionRow(
    BuildContext context,
    ExtensionUiState state,
    ExtensionRow row, {
    required bool last,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<ExtensionCubit>();
    final busy = state.busyIds.contains(row.id);
    final trailing = busy
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: row.installed
                    ? () => cubit.uninstall(row.id)
                    : () => cubit.install(row.id),
                child: Text(
                  row.installed ? l10n.extensionUninstall : l10n.extensionInstall,
                ),
              ),
              Switch(
                value: row.globalEnabled,
                onChanged: row.installed
                    ? (v) => cubit.setGlobalEnabled(row.id, v)
                    : null,
              ),
            ],
          );
    return SettingsLabeledRow(
      title: row.name,
      subtitle: '${_statusText(context, row)} · '
          '${row.homepage.isNotEmpty ? row.homepage : row.description}',
      trailing: trailing,
      showDividerBelow: !last,
    );
  }
}
