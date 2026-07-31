import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/storage/home_target_controller.dart';

/// Non-blocking strip when Android home is a remote SSH profile but storage
/// pool is not connected.
class SshHomeDisconnectedBanner extends StatelessWidget {
  const SshHomeDisconnectedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ConnectionModeService>();
    if (!mode.isSshMode) {
      return const SizedBox.shrink();
    }

    final profileId = context.watch<HomeTargetController>().current.sshProfileId;
    if (profileId == null || profileId.isEmpty) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<SshConnectionCubit, SshConnectionState>(
      buildWhen: (previous, next) {
        final prev = previous.hostsById[profileId]?.status;
        final curr = next.hostsById[profileId]?.status;
        return prev != curr;
      },
      builder: (context, state) {
        final status =
            state.hostsById[profileId]?.status ?? SshHostUiStatus.disconnected;
        if (status == SshHostUiStatus.connected) {
          return const SizedBox.shrink();
        }

        final connecting =
            status == SshHostUiStatus.connecting ||
            status == SshHostUiStatus.reconnecting;
        final l10n = context.l10n;
        final tp = TpTheme.of(context);
        final scheme = Theme.of(context).colorScheme;

        return Material(
          color: scheme.errorContainer.withValues(alpha: 0.92),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tp.spacing.md,
              vertical: tp.spacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.link_off_outlined,
                  size: context.tpIconSizes.md,
                  color: scheme.onErrorContainer,
                ),
                SizedBox(width: tp.spacing.sm),
                Expanded(
                  child: Text(
                    l10n.sshHomeDisconnectedBannerMessage,
                    style: TpTextStyles.of(context).sm.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                SizedBox(width: tp.spacing.sm),
                TpButton(
                  size: TpControlSize.small,
                  onPressed: connecting
                      ? null
                      : () =>
                            context.read<SshConnectionCubit>().connect(profileId),
                  child: Text(
                    connecting
                        ? l10n.termuxSetupConnecting
                        : l10n.sshHomeDisconnectedReconnect,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
