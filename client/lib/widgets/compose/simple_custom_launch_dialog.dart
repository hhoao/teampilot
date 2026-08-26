import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../pages/home_workspace/workspace/config/workspace_cli_effort_helpers.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../cli_launch_config/cli_launch_custom_fields.dart';

/// Explicit Simple launch four-tuple chosen in [showSimpleCustomLaunchDialog].
class SimpleCustomLaunchResult {
  const SimpleCustomLaunchResult({
    required this.cli,
    required this.provider,
    required this.model,
    required this.effort,
  });

  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
}

/// Thin [TpDialog] host around [CliLaunchCustomFields] for Simple custom launch.
///
/// Landing: [lockCli] false, CLI field shown as [CliLaunchCliFieldKind.toolList].
/// Continue: [lockCli] true, CLI field hidden; seed [initialCli] from the session.
Future<SimpleCustomLaunchResult?> showSimpleCustomLaunchDialog(
  BuildContext context, {
  required CliTool? initialCli,
  required String initialProvider,
  required String initialModel,
  required String initialEffort,
  required bool lockCli,
}) {
  assert(!lockCli || initialCli != null, 'lockCli requires initialCli');
  return showDialog<SimpleCustomLaunchResult>(
    context: context,
    builder: (_) => _SimpleCustomLaunchDialog(
      initialCli: initialCli,
      initialProvider: initialProvider,
      initialModel: initialModel,
      initialEffort: initialEffort,
      lockCli: lockCli,
    ),
  );
}

Future<String?> showComposeCustomModelIdDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => TpDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: title,
            onClose: () => Navigator.pop(dialogContext),
          ),
          const SizedBox(height: 16),
          TextField(controller: controller, autofocus: true),
          TpDialogActions(children: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final id = controller.text.trim();
                if (id.isEmpty) return;
                Navigator.pop(dialogContext, id);
              },
              child: Text(confirmLabel),
            ),
          ]),
        ],
      ),
    ),
  );
}

class _SimpleCustomLaunchDialog extends StatefulWidget {
  const _SimpleCustomLaunchDialog({
    required this.initialCli,
    required this.initialProvider,
    required this.initialModel,
    required this.initialEffort,
    required this.lockCli,
  });

  final CliTool? initialCli;
  final String initialProvider;
  final String initialModel;
  final String initialEffort;
  final bool lockCli;

  @override
  State<_SimpleCustomLaunchDialog> createState() =>
      _SimpleCustomLaunchDialogState();
}

class _SimpleCustomLaunchDialogState extends State<_SimpleCustomLaunchDialog> {
  late CliTool? _cli;
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    _cli = widget.lockCli
        ? widget.initialCli!
        : (widget.initialCli ?? CliTool.claude);
    _providerId = widget.initialProvider;
    _modelId = widget.initialModel;
    _effortId = widget.initialEffort;
  }

  bool get _canConfirm => _cli != null;

  CliTool get _catalogCli => _cli ?? CliTool.claude;

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final provider in providers) {
      if (provider.id == _providerId) return provider;
    }
    return null;
  }

  void _confirm() {
    final cli = _cli;
    if (cli == null) return;
    Navigator.of(context).pop(
      SimpleCustomLaunchResult(
        cli: cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = TpSelectDecorations.themed(context);
    final catalogCli = _catalogCli;
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(catalogCli)
        .toList(growable: false);
    final cliItems =
        registry.launchable.map((d) => d.id).toList(growable: false);

    return TpDialog(
      maxWidth: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.workspaceChatLandingCustomLaunchTitle),
          const SizedBox(height: 16),
          CliLaunchCustomFields(
            catalogCli: catalogCli,
            providers: providers,
            providerId: _providerId,
            modelId: _modelId,
            effortId: _effortId,
            registry: registry,
            cliFieldKind: widget.lockCli
                ? CliLaunchCliFieldKind.hidden
                : CliLaunchCliFieldKind.toolList,
            cliItems: cliItems,
            onCliChanged: widget.lockCli
                ? null
                : (cli) => setState(() {
                    _cli = cli;
                    _providerId = '';
                    _modelId = '';
                    _effortId = '';
                  }),
            effortContext: CliLaunchEffortContext.standalone,
            dropdownKeyPrefix: 'simple-custom-launch',
            decoration: dropdownDeco,
            onProviderChanged: (value) => setState(() {
              _providerId = value;
              _modelId = '';
              _effortId = '';
            }),
            onModelChanged: (value) => setState(() {
              _modelId = value.trim();
              if (!workspaceCliShowsEffortPicker(
                registry: registry,
                cli: catalogCli,
                provider: _selectedProvider(providers),
                model: _modelId,
              )) {
                _effortId = '';
              }
            }),
            onEffortChanged: (value) =>
                setState(() => _effortId = value.trim()),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _canConfirm ? _confirm : null,
                child: Text(l10n.confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
