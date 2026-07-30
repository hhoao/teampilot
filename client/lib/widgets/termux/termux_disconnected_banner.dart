import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/termux_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/connection_mode_service.dart';

/// Non-blocking strip when Android home is Termux but the loopback SSH link is down.
class TermuxDisconnectedBanner extends StatelessWidget {
  const TermuxDisconnectedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ConnectionModeService>();
    if (!mode.isTermuxMode) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<TermuxCubit, TermuxState>(
      buildWhen: (previous, next) =>
          previous.connected != next.connected ||
          previous.connecting != next.connecting,
      builder: (context, state) {
        if (state.connected) {
          return const SizedBox.shrink();
        }

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
                    l10n.termuxDisconnectedBannerMessage,
                    style: TpTextStyles.of(context).sm.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                SizedBox(width: tp.spacing.sm),
                TpButton(
                  size: TpControlSize.small,
                  onPressed: state.connecting
                      ? null
                      : () => context.read<TermuxCubit>().reconnect(),
                  child: Text(
                    state.connecting
                        ? l10n.termuxSetupConnecting
                        : l10n.termuxDisconnectedReconnect,
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
