import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import 'expert_hub_body.dart';
import 'expert_hub_detail_overlay.dart';

/// Landing / automation picker — returns the selected expert key, or `null`.
Future<String?> showExpertLandingPickerSheet(
  BuildContext context, {
  String? selectedKey,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => ExpertLandingPickerDialog(
      selectedKey: selectedKey,
    ),
  );
}

/// Apply-mode picker for team member config — invokes [onApply] on confirm.
Future<void> showExpertApplyPickerSheet(
  BuildContext context, {
  required ValueChanged<DiscoverableMember> onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ExpertLandingPickerDialog(
      onApply: onApply,
    ),
  );
}

/// Expert Hub–style dialog: card grid → detail → Confirm.
class ExpertLandingPickerDialog extends StatefulWidget {
  const ExpertLandingPickerDialog({
    this.selectedKey,
    this.onApply,
    super.key,
  });

  final String? selectedKey;

  /// When set, Confirm applies the member and closes without returning a key.
  final ValueChanged<DiscoverableMember>? onApply;

  @override
  State<ExpertLandingPickerDialog> createState() =>
      _ExpertLandingPickerDialogState();
}

class _ExpertLandingPickerDialogState extends State<ExpertLandingPickerDialog> {
  DiscoverableMember? _detail;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ExpertHubCubit>();
    if (cubit.state.allMembers.isEmpty &&
        cubit.state.status != ExpertHubLoadStatus.loading) {
      unawaited(cubit.load());
    }
  }

  void _confirm(DiscoverableMember member) {
    final onApply = widget.onApply;
    if (onApply != null) {
      onApply(member);
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(member.key);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return PopScope(
      canPop: _detail == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_detail != null) {
          setState(() => _detail = null);
        }
      },
      child: TpDialog(
        maxWidth: 960,
        maxHeight: maxHeight,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SizedBox(
          height: maxHeight - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.expertHubTitle),
              const SizedBox(height: 8),
              Expanded(
                child: BlocConsumer<ExpertHubCubit, ExpertHubState>(
                  listenWhen: (a, b) =>
                      a.errorMessage != b.errorMessage &&
                      b.errorMessage != null,
                  listener: (context, state) {
                    if (state.errorMessage == null) return;
                    AppToast.show(
                      context,
                      message: context.l10n.expertHubLoadError,
                      variant: TpToastVariant.error,
                    );
                    context.read<ExpertHubCubit>().clearError();
                  },
                  builder: (context, state) {
                    final cubit = context.read<ExpertHubCubit>();
                    final detail = _detail;
                    if (detail != null) {
                      return ExpertHubDetailOverlay(
                        key: ValueKey(detail.key),
                        member: detail,
                        favorited: state.favorites.contains(detail.key),
                        adding: state.addingKeys.contains(detail.key),
                        installedDepIds: state.installedDepIds,
                        pickerMode: true,
                        inset: 12,
                        onBack: () => setState(() => _detail = null),
                        onToggleFavorite: () =>
                            cubit.toggleFavorite(detail.key),
                        onConfirm: () => _confirm(detail),
                        onAddToTeam: () {},
                        onLaunchInWorkspace: () {},
                      );
                    }
                    return ExpertHubBody(
                      cubit: cubit,
                      showCreate: false,
                      selectedKey: widget.selectedKey,
                      inset: 12,
                      onOpen: (m) => setState(() => _detail = m),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
