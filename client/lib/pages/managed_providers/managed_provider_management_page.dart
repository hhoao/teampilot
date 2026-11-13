import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'managed_provider_editor_page.dart';
import '../../utils/managed_provider_error_localization.dart';
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
  ManagedProvider? _editingProvider;
  bool _isEditing = false;

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
              previous.errorCode != current.errorCode &&
              current.errorCode != null,
          listener: (context, state) {
            AppToast.show(
              context,
              message: managedProviderErrorMessage(
                context.l10n,
                providerCode: state.errorCode,
                detail: state.errorMessage,
              ),
              variant: TpToastVariant.error,
            );
          },
        ),
        BlocListener<ManagedProviderUsageCubit, ManagedProviderUsageState>(
          listenWhen: (previous, current) =>
              previous.errorCode != current.errorCode &&
              current.errorCode != null &&
              current.errorCode != ManagedProviderUsageErrorCode.queryFailed,
          listener: (context, state) {
            AppToast.show(
              context,
              message: managedProviderErrorMessage(
                context.l10n,
                usageCode: state.errorCode,
                detail: state.errorMessage,
              ),
              variant: TpToastVariant.error,
            );
          },
        ),
      ],
      child: KeyedSubtree(
        key: const Key('managed-provider-management-page'),
        child: _isEditing
            ? ManagedProviderEditorPage(
                key: const Key('managed-provider-editor-page'),
                provider: _editingProvider,
                embedded: true,
                onBack: _closeEditor,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WorkspacePaneHeader(
                    title: context.l10n.managedProviders.title,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('managed-provider-add'),
                      onPressed: () => _openEditor(context),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.managedProviders.add),
                    ),
                  ),
                  Expanded(
                    child:
                        BlocBuilder<ManagedProviderCubit, ManagedProviderState>(
                          builder: (context, providerState) {
                            if (providerState.status ==
                                    ManagedProviderLoadStatus.loading &&
                                providerState.providers.isEmpty) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (providerState.status ==
                                    ManagedProviderLoadStatus.error &&
                                providerState.providers.isEmpty) {
                              return _LoadError(
                                message: managedProviderErrorMessage(
                                  context.l10n,
                                  providerCode: providerState.errorCode,
                                  detail: providerState.errorMessage,
                                ),
                                onRetry: () =>
                                    context.read<ManagedProviderCubit>().load(),
                              );
                            }
                            // Usage state is selected per card inside the list;
                            // a snapshot refresh must not rebuild every card.
                            return ManagedProviderList(
                              providers: providerState.providers,
                              onEdit: (provider) =>
                                  _openEditor(context, provider: provider),
                              onToggle: _toggle,
                              onDelete: _delete,
                              onRefresh: _refresh,
                            );
                          },
                        ),
                  ),
                ],
              ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      body: SafeArea(
        child: Padding(padding: WorkspacePaneInsets.page, child: content),
      ),
    );
  }

  void _openEditor(BuildContext context, {ManagedProvider? provider}) {
    if (!widget.embedded) {
      Navigator.of(context).push<void>(
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
      return;
    }
    setState(() {
      _editingProvider = provider;
      _isEditing = true;
    });
  }

  void _closeEditor() {
    if (!mounted) return;
    setState(() {
      _editingProvider = null;
      _isEditing = false;
    });
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.managedProviders.deleteTitle),
        content: Text(
          context.l10n.managedProviders.deleteContent(name: provider.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.managedProviders.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.managedProviders.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cubit = context.read<ManagedProviderCubit>();
    await cubit.delete(provider.id);
    if (!mounted || cubit.state.errorCode == null) return;
    AppToast.show(
      context,
      message: managedProviderErrorMessage(
        context.l10n,
        providerCode: cubit.state.errorCode,
        detail: cubit.state.errorMessage,
      ),
      variant: TpToastVariant.error,
    );
  }

  Future<void> _refresh(ManagedProvider provider) async {
    await context.read<ManagedProviderUsageCubit>().refreshOne(provider.id);
  }
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
        Text(
          message,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(context).sm,
        ),
        const SizedBox(height: 12),
        TpButton(
          variant: TpButtonVariant.outline,
          onPressed: onRetry,
          child: Text(context.l10n.managedProviders.retry),
        ),
      ],
    ),
  );
}
