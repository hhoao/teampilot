import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../services/cli/cli_installer_service.dart';
import 'settings/workspace_settings_widgets.dart';

class CliInstallProgressPanel extends StatelessWidget {
  const CliInstallProgressPanel({
    super.key,
    required this.phase,
    this.logLines = const [],
  });

  final CliInstallPhase phase;
  final List<String> logLines;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SettingsSurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              borderRadius: BorderRadius.circular(4),
              backgroundColor: cs.surfaceContainerHighest,
            ),
            const SizedBox(height: 10),
            Text(
              _phaseLabel(l10n, phase),
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (logLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    logLines.join('\n'),
                    style: tt.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(AppLocalizations l10n, CliInstallPhase phase) {
    return switch (phase) {
      CliInstallPhase.checkingNpm => l10n.cliInstallProgressCheckingNpm,
      CliInstallPhase.bootstrappingNode => l10n.cliInstallProgressBootstrappingNode,
      CliInstallPhase.installingCli => l10n.cliInstallProgressInstallingCli,
      CliInstallPhase.locatingExecutable =>
        l10n.cliInstallProgressLocatingExecutable,
    };
  }
}
