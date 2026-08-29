import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../services/provider_usage/official_managed_provider_binding.dart';
import '../../widgets/app_provider/provider_credential_action_bar.dart';

/// Login / import / revoke for `cli:` Managed Provider credential sources.
class ManagedProviderOfficialCredentials extends StatefulWidget {
  const ManagedProviderOfficialCredentials({
    required this.credentialSource,
    super.key,
  });

  final String credentialSource;

  @override
  State<ManagedProviderOfficialCredentials> createState() =>
      _ManagedProviderOfficialCredentialsState();
}

class _ManagedProviderOfficialCredentialsState
    extends State<ManagedProviderOfficialCredentials> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensure());
    });
  }

  @override
  void didUpdateWidget(covariant ManagedProviderOfficialCredentials oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.credentialSource != widget.credentialSource) {
      unawaited(_ensure());
    }
  }

  Future<void> _ensure() async {
    final binding = OfficialManagedProviderBinding.forCredentialSource(
      widget.credentialSource,
    );
    if (binding == null || !mounted) return;
    await ensureOfficialAppProvider(
      cubit: context.read<AppProviderCubit>(),
      binding: binding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final binding = OfficialManagedProviderBinding.forCredentialSource(
      widget.credentialSource,
    );
    if (binding == null) return const SizedBox.shrink();
    return BlocBuilder<AppProviderCubit, AppProviderState>(
      builder: (context, state) {
        final provider =
            state
                .providersFor(binding.cli)
                .where((item) => item.id == binding.appProviderId)
                .firstOrNull ??
            binding.template;
        return ProviderCredentialActionBar(
          key: const Key('managed-provider-official-credentials'),
          provider: provider,
          ensureSaved: () => ensureOfficialAppProvider(
            cubit: context.read<AppProviderCubit>(),
            binding: binding,
          ),
        );
      },
    );
  }
}
