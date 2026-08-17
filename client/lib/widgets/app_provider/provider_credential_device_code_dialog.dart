import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Modal device-code wait UI (GitHub-style copy, dialog chrome).
class ProviderCredentialDeviceCodeDialog extends StatelessWidget {
  const ProviderCredentialDeviceCodeDialog({super.key});

  static Future<void> show(
    BuildContext context, {
    required AppProviderCubit cubit,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => BlocProvider<AppProviderCubit>.value(
        value: cubit,
        child: const ProviderCredentialDeviceCodeDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppProviderCubit, AppProviderState>(
      buildWhen: (previous, current) =>
          previous.credentialLoginDeviceCode !=
              current.credentialLoginDeviceCode ||
          previous.credentialLoginVerificationUri !=
              current.credentialLoginVerificationUri,
      builder: (context, state) {
        final code = state.credentialLoginDeviceCode ?? '';
        final uri = state.credentialLoginVerificationUri?.trim() ?? '';
        return TpDialog(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.providerCredentialsDeviceCodeTitle),
              const SizedBox(height: 16),
              Text(
                l10n.providerCredentialsBrowserOpened,
                style: TpTextStyles.of(context).mutedSm,
              ),
              const SizedBox(height: 8),
              SelectableText(
                code,
                key: const Key('provider-device-code'),
                style: TpTextStyles.of(context).mdBoldTightSnug,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.providerCredentialsDeviceCodeHint,
                style: TpTextStyles.of(context).mutedSm,
              ),
              if (uri.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  uri,
                  key: const Key('provider-device-verification-uri'),
                  style: TpTextStyles.of(context).sm,
                ),
              ],
              TpDialogActions(
                children: [
                  TpButton(
                    variant: TpButtonVariant.outline,
                    onPressed: () {
                      unawaited(
                        context
                            .read<AppProviderCubit>()
                            .reopenCredentialLoginBrowser(),
                      );
                    },
                    child: Text(l10n.providerCredentialsReopenBrowser),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
