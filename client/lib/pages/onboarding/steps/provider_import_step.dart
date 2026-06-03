import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_provider_config.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';

class OnboardingProviderImportStep extends StatefulWidget {
  const OnboardingProviderImportStep({super.key});

  @override
  State<OnboardingProviderImportStep> createState() =>
      _OnboardingProviderImportStepState();
}

class _OnboardingProviderImportStepState
    extends State<OnboardingProviderImportStep> {
  var _importing = false;
  var _imported = false;
  List<AppProviderConfig> _providers = const [];
  String _statusMessage = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_import());
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final cubit = context.read<AppProviderCubit>();
      await cubit.setSelectedCli(AppProviderCli.claude);
      final result = await cubit.importFromExternal();
      if (!mounted) return;
      setState(() {
        _importing = false;
        _imported = true;
        _providers = cubit.state.providersFor(AppProviderCli.claude);
        _statusMessage = cubit.state.statusMessage;
      });
      if (!result.changed && _providers.isEmpty) {
        setState(
          () => _statusMessage = context.l10n.onboardingProviderImportEmpty,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _imported = true;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingProviderImportTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingProviderImportSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (!_importing)
          if (_error != null)
            SettingsSurfaceCard(
              child: ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(l10n.onboardingProviderImportFailed),
                subtitle: Text('$_error'),
              ),
            )
          else if (_providers.isEmpty)
            SettingsSurfaceCard(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.onboardingProviderImportEmpty),
                subtitle: _statusMessage.isEmpty ? null : Text(_statusMessage),
              ),
            )
          else
            SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroupHeader(title: l10n.onboardingProviderImportResults),
                for (var i = 0; i < _providers.length; i++) ...[
                  ListTile(
                    title: Text(_providers[i].name),
                    subtitle: Text(
                      _providers[i].defaultModel.isEmpty
                          ? _providers[i].id
                          : _providers[i].defaultModel,
                    ),
                    trailing: const Icon(Icons.check, size: AppIconSizes.md),
                  ),
                  if (i < _providers.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        if (_imported && !_importing) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.refresh, size: AppIconSizes.md),
              label: Text(l10n.onboardingProviderImportRescan),
            ),
          ),
        ],
      ],
    );
  }
}
