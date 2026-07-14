import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_provider_config.dart';
import '../../../widgets/app_provider/provider_brand_icon.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import 'onboarding_step_scaffold.dart';

class OnboardingProviderImportStep extends StatefulWidget {
  const OnboardingProviderImportStep({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<OnboardingProviderImportStep> createState() =>
      _OnboardingProviderImportStepState();
}

class _OnboardingProviderImportStepState
    extends State<OnboardingProviderImportStep> {
  var _importing = false;
  var _imported = false;
  var _hasStartedImport = false;
  List<AppProviderConfig> _providers = const [];
  String _statusMessage = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startImportIfNeeded();
    }
  }

  @override
  void didUpdateWidget(OnboardingProviderImportStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _startImportIfNeeded();
    }
  }

  void _startImportIfNeeded() {
    if (_hasStartedImport) return;
    _hasStartedImport = true;
    unawaited(_import());
  }

  List<AppProviderConfig> _allProviders(AppProviderCubit cubit) {
    return [
      for (final cli in CliTool.values) ...cubit.state.providersFor(cli),
    ];
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final cubit = context.read<AppProviderCubit>();
      final results = await cubit.importAllFromExternal();
      if (!mounted) return;
      final providers = _allProviders(cubit);
      final changed = results.any((r) => r.changed);
      setState(() {
        _importing = false;
        _imported = true;
        _providers = providers;
        _statusMessage = cubit.state.statusMessage;
      });
      if (!changed && providers.isEmpty) {
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

    return OnboardingStepScaffold(
      title: l10n.onboardingProviderImportTitle,
      subtitle: l10n.onboardingProviderImportSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_importing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
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
                leading: Icon(Icons.info_outline),
                title: Text(l10n.onboardingProviderImportEmpty),
                subtitle: _statusMessage.isEmpty ? null : Text(_statusMessage),
              ),
            )
          else
            SettingsSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsGroupHeader(
                    title: l10n.onboardingProviderImportResults,
                  ),
                  for (var i = 0; i < _providers.length; i++) ...[
                    ListTile(
                      leading: ProviderBrandIcon.fromConfig(
                        _providers[i],
                        size: 32,
                        borderRadius: 8,
                      ),
                      title: Text(_providers[i].name),
                      subtitle: Text(
                        [
                          _providers[i].cli.value,
                          if (_providers[i].defaultModel.isNotEmpty)
                            _providers[i].defaultModel
                          else
                            _providers[i].id,
                        ].join(' · '),
                      ),
                      trailing: Icon(
                        Icons.check,
                        size: context.appIconSizes.md,
                      ),
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
                icon: Icon(Icons.refresh, size: context.appIconSizes.md),
                label: Text(l10n.onboardingProviderImportRescan),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
