import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/cli/registry/capabilities/provider_capability.dart';
import 'compose_model_preset_chip.dart';

/// Shows the per-model context-window editor and persists the result on the
/// provider row. The menu rebuilds from [AppProviderCubit] state on the next
/// build, so the new value shows up the next time the menu opens.
Future<void> showComposeContextWindowEditor(
  BuildContext context, {
  required CascadeContextWindowEditRequest request,
}) async {
  AppProviderCubit cubit;
  try {
    cubit = context.read<AppProviderCubit>();
  } on ProviderNotFoundException {
    return;
  }
  final provider = cubit.state
      .providersFor(request.cli)
      .where((p) => p.id == request.providerId)
      .firstOrNull;
  if (provider == null) return;

  final current = resolveModelContextWindow(
    provider,
    model: request.modelId,
    entryId: request.modelId,
  );
  final result = await showContextWindowEditDialog(
    context,
    modelName: request.modelId,
    currentTokens: current,
  );
  if (result == null) return;
  final config = configWithModelContextWindow(
    provider.config,
    request.modelId,
    result == 0 ? null : result,
  );
  await cubit.upsertProvider(provider.copyWith(config: config));
}

/// Writes a window picked from the standalone selector (no dialog).
Future<void> applyComposeContextWindowPick(
  BuildContext context, {
  required CascadeContextWindowPick request,
}) async {
  AppProviderCubit cubit;
  try {
    cubit = context.read<AppProviderCubit>();
  } on ProviderNotFoundException {
    return;
  }
  final provider = cubit.state
      .providersFor(request.cli)
      .where((p) => p.id == request.providerId)
      .firstOrNull;
  if (provider == null) return;
  final config = configWithModelContextWindow(
    provider.config,
    request.modelId,
    request.tokens,
  );
  await cubit.upsertProvider(provider.copyWith(config: config));
}

/// Returns null when cancelled, `0` to clear (use the model default), or a
/// positive token count to set.
Future<int?> showContextWindowEditDialog(
  BuildContext context, {
  required String modelName,
  required int? currentTokens,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _ContextWindowEditDialog(
      modelName: modelName,
      currentTokens: currentTokens,
    ),
  );
}

class _ContextWindowEditDialog extends StatefulWidget {
  const _ContextWindowEditDialog({
    required this.modelName,
    required this.currentTokens,
  });

  final String modelName;
  final int? currentTokens;

  @override
  State<_ContextWindowEditDialog> createState() =>
      _ContextWindowEditDialogState();
}

class _ContextWindowEditDialogState extends State<_ContextWindowEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentTokens?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.modelContextWindowEditTitle(model: widget.modelName),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.modelContextWindow,
              hintText: l10n.modelContextWindowHint,
            ),
          ),
          if (widget.currentTokens != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: Text(l10n.modelContextWindowUseDefault),
              ),
            ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton(onPressed: _save, child: Text(l10n.save)),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    final raw = _controller.text.trim();
    final value = raw.isEmpty ? 0 : (int.tryParse(raw) ?? 0);
    Navigator.pop(context, value);
  }
}
