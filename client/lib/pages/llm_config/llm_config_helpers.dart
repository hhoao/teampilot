import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';

Future<String?> saveNewAppProvider(
  BuildContext context,
  AppProviderConfig draft,
) async {
  final appCubit = context.read<AppProviderCubit>();

  final existingIds = appCubit.state.providersFor(draft.cli).map((p) => p.id);
  final baseId = draft.id.trim().isNotEmpty
      ? draft.id.trim()
      : AppProviderCubit.slugifyId(draft.name);
  final id = AppProviderCubit.uniqueId(baseId, existingIds);
  final provider = draft.copyWith(id: id, name: draft.name.trim());

  await appCubit.upsertProvider(provider);
  return id;
}

Future<void> saveExistingAppProvider(
  BuildContext context,
  AppProviderConfig existing, {
  required AppProviderConfig draft,
}) async {
  final appCubit = context.read<AppProviderCubit>();
  await appCubit.upsertProvider(
    draft.copyWith(id: existing.id, cli: existing.cli),
  );
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
  final hasCredentials = provider?.hasClaudeCredentialsReady ?? false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteProvider),
      content: Text(
        hasCredentials
            ? l10n.deleteProviderWithCredentialsConfirm(label)
            : l10n.deleteProviderConfirm(label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await context.read<AppProviderCubit>().deleteProvider(id);
  }
}
