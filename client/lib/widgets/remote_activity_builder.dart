import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_remote_activity_cubit.dart';

typedef RemoteActivityWidgetBuilder =
    Widget Function(BuildContext context, SessionRemoteActivityState state);

/// Rebuilds [builder] from [SessionRemoteActivityCubit] when the app provides
/// it, and falls back to an empty projection in tests/single-device builds.
class RemoteActivityBuilder extends StatelessWidget {
  const RemoteActivityBuilder({required this.builder, super.key});

  final RemoteActivityWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final cubit = _maybeRead(context);
    if (cubit == null) {
      return builder(context, const SessionRemoteActivityState());
    }
    return BlocBuilder<SessionRemoteActivityCubit, SessionRemoteActivityState>(
      bloc: cubit,
      builder: builder,
    );
  }

  static SessionRemoteActivityCubit? _maybeRead(BuildContext context) {
    try {
      return context.read<SessionRemoteActivityCubit>();
    } on Object {
      return null;
    }
  }
}

/// Current remote projection, or `null` when the app is not running the
/// session-plane client. Safe to call from a widget build; it subscribes with
/// `context.select` when the cubit is present.
SessionRemoteActivityState? maybeRemoteActivity(BuildContext context) {
  try {
    return context
        .select<SessionRemoteActivityCubit, SessionRemoteActivityState>(
          (cubit) => cubit.state,
        );
  } on Object {
    return null;
  }
}

/// First busy seat on [sessionId], or `null`.
String? remoteBusyMemberId(SessionRemoteActivityState state, String sessionId) {
  for (final seat in state.session(sessionId)?.seats ?? const []) {
    if (seat.isBusy) return seat.memberId;
  }
  return null;
}
