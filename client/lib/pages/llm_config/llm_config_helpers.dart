import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'package:shared_ui/shared_ui.dart';

Future<String?> saveNewAppProvider(
  BuildContext context,
  AppProviderConfig draft,
) async {
  final appCubit = context.read<AppProviderCubit>();

  final existing = appCubit.state.providersFor(draft.cli);
  final baseId = draft.id.trim().isNotEmpty
      ? draft.id.trim()
      : AppProviderCubit.slugifyId(draft.name);
  final sameId = existing.where((p) => p.id == baseId).firstOrNull;
  // Keep a form-assigned id (also the row a form-side login already created
  // with its credentials); bump only when baseId belongs to another identity.
  final id =
      sameId == null ||
          (sameId.cli == draft.cli &&
              sameId.category == draft.category &&
              sameId.name == draft.name)
      ? baseId
      : AppProviderCubit.uniqueId(baseId, existing.map((p) => p.id));
  final provider = draft.copyWith(id: id, name: draft.name.trim());

  final saved = await appCubit.upsertProvider(
    provider,
    captureVaultCredentials: true,
  );
  if (!saved) {
    if (context.mounted) {
      AppToast.show(
        context,
        message: context.l10n.vaultLockedSaveBlocked,
        variant: TpToastVariant.error,
      );
    }
    return null;
  }
  return id;
}

Future<bool> saveExistingAppProvider(
  BuildContext context,
  AppProviderConfig existing, {
  required AppProviderConfig draft,
}) async {
  final appCubit = context.read<AppProviderCubit>();
  final saved = await appCubit.upsertProvider(
    draft.copyWith(id: existing.id, cli: existing.cli),
    captureVaultCredentials: true,
  );
  if (!saved && context.mounted) {
    AppToast.show(
      context,
      message: context.l10n.vaultLockedSaveBlocked,
      variant: TpToastVariant.error,
    );
  }
  return saved;
}

Future<void> confirmDeleteAppProvider(BuildContext context, String id) async {
  final l10n = context.l10n;
  final provider = context
      .read<AppProviderCubit>()
      .state
      .providers
      .where((p) => p.id == id)
      .firstOrNull;
  final label = provider?.name ?? id;
  final hasCredentials = provider?.hasCredentialsReady ?? false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.deleteProvider,
            onClose: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(height: 16),
          Text(
            hasCredentials
                ? l10n.deleteProviderWithCredentialsConfirm(label)
                : l10n.deleteProviderConfirm(label),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed == true && context.mounted) {
    await context.read<AppProviderCubit>().deleteProvider(id);
  }
}
