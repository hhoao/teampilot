import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/ui/app_keys.dart';

/// Bootstrap hard-fail UI with retry and optional escape hatches.
class BootstrapStartupErrorPage extends StatelessWidget {
  const BootstrapStartupErrorPage({
    super.key,
    required this.error,
    required this.showChooseWorkEnvironment,
    required this.showNativeStorageFallback,
    required this.retrying,
    required this.onRetry,
    this.onChooseWorkEnvironment,
    this.onNativeStorageFallback,
  });

  final Object error;
  final bool showChooseWorkEnvironment;
  final bool showNativeStorageFallback;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback? onChooseWorkEnvironment;
  final VoidCallback? onNativeStorageFallback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.bootstrapStartupFailed(error.toString())),
              const SizedBox(height: 16),
              FilledButton(
                key: AppKeys.bootstrapRetryButton,
                onPressed: retrying ? null : onRetry,
                child: retrying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.bootstrapRetry),
              ),
              if (showChooseWorkEnvironment) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  key: AppKeys.bootstrapChooseWorkEnvironmentButton,
                  onPressed: retrying ? null : onChooseWorkEnvironment,
                  child: retrying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.bootstrapChooseWorkEnvironment),
                ),
              ],
              if (showNativeStorageFallback) ...[
                const SizedBox(height: 12),
                FilledButton(
                  key: AppKeys.bootstrapNativeStorageFallbackButton,
                  onPressed: retrying ? null : onNativeStorageFallback,
                  child: retrying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.bootstrapUseNativeStorageInstead),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
