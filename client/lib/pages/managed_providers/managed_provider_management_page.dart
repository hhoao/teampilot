import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../models/managed_provider.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'managed_provider_editor_page.dart';
import 'managed_provider_list.dart';

class ManagedProviderManagementPage extends StatefulWidget {
  const ManagedProviderManagementPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<ManagedProviderManagementPage> createState() =>
      _ManagedProviderManagementPageState();
}

class _ManagedProviderManagementPageState
    extends State<ManagedProviderManagementPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final providers = context.read<ManagedProviderCubit>();
      if (providers.state.status == ManagedProviderLoadStatus.initial) {
        unawaited(providers.load());
      }
      final usage = context.read<ManagedProviderUsageCubit>();
      if (usage.state.status == ManagedProviderUsageLoadStatus.initial) {
        unawaited(usage.load());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = MultiBlocListener(
      listeners: [
        BlocListener<ManagedProviderCubit, ManagedProviderState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage &&
              current.errorMessage != null,
          listener: (context, state) {
            AppToast.show(
              context,
              message: state.errorMessage!,
              variant: TpToastVariant.error,
            );
          },
        ),
        BlocListener<ManagedProviderUsageCubit, ManagedProviderUsageState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage &&
              current.errorMessage != null,
          listener: (context, state) {
            AppToast.show(
              context,
              message: state.errorMessage!,
              variant: TpToastVariant.error,
            );
          },
        ),
      ],
      child: Column(
        key: const Key('managed-provider-management-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(onAdd: () => _openEditor(context)),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<ManagedProviderCubit, ManagedProviderState>(
              builder: (context, providerState) {
                if (providerState.status == ManagedProviderLoadStatus.loading &&
                    providerState.providers.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (providerState.status == ManagedProviderLoadStatus.error &&
                    providerState.providers.isEmpty) {
                  return _LoadError(
                    message:
                        providerState.errorMessage ??
                        'Unable to load managed providers.',
                    onRetry: () => context.read<ManagedProviderCubit>().load(),
                  );
                }
                return BlocBuilder<
                  ManagedProviderUsageCubit,
                  ManagedProviderUsageState
                >(
                  builder: (context, usageState) => ManagedProviderList(
                    providers: providerState.providers,
                    snapshots: usageState.snapshots,
                    isRefreshing: usageState.isRefreshingProvider,
                    onEdit: (provider) =>
                        _openEditor(context, provider: provider),
                    onToggle: _toggle,
                    onDelete: _delete,
                    onRefresh: _refresh,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: content),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    ManagedProvider? provider,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<ManagedProviderCubit>()),
            BlocProvider.value(
              value: context.read<ManagedProviderUsageCubit>(),
            ),
          ],
          child: ManagedProviderEditorPage(provider: provider),
        ),
      ),
    );
  }

  Future<void> _toggle(ManagedProvider provider) async {
    final cubit = context.read<ManagedProviderCubit>();
    if (provider.enabled) {
      await cubit.disable(provider.id);
    } else {
      await cubit.enable(provider.id);
    }
  }

  Future<void> _delete(ManagedProvider provider) async {
    await context.read<ManagedProviderCubit>().delete(provider.id);
  }

  Future<void> _refresh(ManagedProvider provider) async {
    await context.read<ManagedProviderUsageCubit>().refreshOne(provider.id);
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Managed Providers',
              style: TpTextStyles.of(
                context,
              ).xl.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Balances and quotas independent from CLI provider configuration.',
              style: TpTextStyles.of(
                context,
              ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      TpButton(
        key: const Key('managed-provider-add'),
        onPressed: onAdd,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18),
            SizedBox(width: 6),
            Text('Add provider'),
          ],
        ),
      ),
    ],
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TpButton(
          variant: TpButtonVariant.outline,
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}
