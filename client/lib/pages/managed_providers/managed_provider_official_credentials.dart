import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../services/provider_usage/managed_provider_cli_binding.dart';
import '../../widgets/app_provider/provider_credential_action_bar.dart';

/// Login / import / revoke for `cli:` Managed Provider credential sources.
///
/// Binds to the entry's dedicated CLI provider row (`<cli>-mp-<entryId>`)
/// so login lands in that entry's isolated HOME.
class ManagedProviderOfficialCredentials extends StatefulWidget {
  const ManagedProviderOfficialCredentials({
    required this.credentialSource,
    required this.managedProviderId,
    required this.managedProviderName,
    super.key,
  });

  final String credentialSource;
  final String managedProviderId;
  final String managedProviderName;

  @override
  State<ManagedProviderOfficialCredentials> createState() =>
      _ManagedProviderOfficialCredentialsState();
}

class _ManagedProviderOfficialCredentialsState
    extends State<ManagedProviderOfficialCredentials> {
  static const _binding = ManagedProviderCliBinding();

  AppProviderConfig? _dedicatedRow() {
    final cli = _binding.cliForCredentialSource(widget.credentialSource);
    if (cli == null) return null;
    final rowId = managedProviderCliRowId(cli, widget.managedProviderId);
    final existing = context
        .read<AppProviderCubit>()
        .state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
    if (existing != null) return existing;
    return _binding.rowTemplateFor(
      cli,
      widget.managedProviderId,
      widget.managedProviderName,
    );
  }

  Future<AppProviderConfig?> _ensureSaved() async {
    final cli = _binding.cliForCredentialSource(widget.credentialSource);
    if (cli == null) return null;
    final rowId = managedProviderCliRowId(cli, widget.managedProviderId);
    final cubit = context.read<AppProviderCubit>();
    final existing = cubit.state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
    if (existing != null) return existing;
    final template = _binding.rowTemplateFor(
      cli,
      widget.managedProviderId,
      widget.managedProviderName,
    );
    if (template == null) return null;
    final ok = await cubit.upsertProvider(template);
    if (!ok) return null;
    return cubit.state
        .providersFor(cli)
        .where((row) => row.id == rowId)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final row = _dedicatedRow();
    if (row == null) return const SizedBox.shrink();
    return BlocBuilder<AppProviderCubit, AppProviderState>(
      builder: (context, state) {
        final cli = row.cli;
        final rowId = row.id;
        final provider =
            state
                .providersFor(cli)
                .where((item) => item.id == rowId)
                .firstOrNull ??
            row;
        return ProviderCredentialActionBar(
          key: const Key('managed-provider-official-credentials'),
          provider: provider,
          ensureSaved: _ensureSaved,
        );
      },
    );
  }
}
