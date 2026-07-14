import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../services/expert_hub/member_roster_service.dart';
import '../../widgets/app_dialog.dart';
import '../home_workspace/home_workspace_global_section.dart';
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
      hostContext: context,
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
      hostContext: context,
      onApply: onApply,
    ),
  );
}

/// Expert Hub–style dialog: card grid → detail → Confirm.
class ExpertLandingPickerDialog extends StatefulWidget {
  const ExpertLandingPickerDialog({
    required this.hostContext,
    this.selectedKey,
    this.onApply,
    super.key,
  });

  /// Context that opened the dialog — used after Launch dismisses this route.
  final BuildContext hostContext;

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

  Future<void> _addToTeam(
    ExpertHubCubit cubit,
    DiscoverableMember member,
  ) async {
    final l10n = context.l10n;
    try {
      await expertHubAddToTeam(context, cubit, member);
      if (!mounted) return;
      setState(() => _detail = null);
    } on MemberAddException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.expertHubAddFailed,
        variant: AppToastVariant.error,
      );
    }
  }

  void _launchInWorkspace(DiscoverableMember member) {
    final host = widget.hostContext;
    Navigator.of(context).pop();
    expertHubLaunchInWorkspace(host, member);
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
      child: AppDialog(
        maxWidth: 960,
        maxHeight: maxHeight,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SizedBox(
          height: maxHeight - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(title: l10n.expertHubTitle),
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
                      variant: AppToastVariant.error,
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
                        onAddToTeam: () => unawaited(_addToTeam(cubit, detail)),
                        onLaunchInWorkspace: () =>
                            _launchInWorkspace(detail),
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
