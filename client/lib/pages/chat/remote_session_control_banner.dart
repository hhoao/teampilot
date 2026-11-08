import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_remote_activity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/session_protocol/session_models.dart';
import '../../services/session_sync/session_protocol_controller.dart';

/// Compact "desktop is working — stop it" control shown on a remote viewer.
///
/// Optional providers keep the widget inert in tests and single-device builds.
class RemoteSessionControlBanner extends StatelessWidget {
  const RemoteSessionControlBanner({
    required this.sessionId,
    required this.memberId,
    super.key,
  });

  final String sessionId;
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final cubit = _maybeRead<SessionRemoteActivityCubit>(context);
    final protocol = _maybeRead<SessionProtocolController>(context);
    if (cubit == null || protocol == null || !protocol.isClient) {
      return const SizedBox.shrink();
    }
    return BlocBuilder<SessionRemoteActivityCubit, SessionRemoteActivityState>(
      bloc: cubit,
      builder: (context, state) {
        SessionSeatActivity? busy;
        for (final seat in state.session(sessionId)?.seats ?? const []) {
          if (seat.isBusy) {
            busy = seat;
            break;
          }
        }
        if (busy == null) return const SizedBox.shrink();
        final targetMemberId = busy.memberId;
        final l10n = context.l10n;
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () async {
              final result = await protocol.cancelTurn(
                sessionId: sessionId,
                memberId: targetMemberId,
              );
              if (!context.mounted || result.ok) return;
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(result.code)));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_circle_outlined, size: 16, color: cs.error),
                  const SizedBox(width: 6),
                  Text(l10n.cancel, style: TpTextStyles.of(context).xsSemibold),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on Object {
      return null;
    }
  }
}
