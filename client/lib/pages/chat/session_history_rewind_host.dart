import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../pages/home_workspace/workspace/workspace_session_actions.dart';
import '../../services/chat/conversation/history/later_checkpoint_messages.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/app_toast/app_toast.dart';

final class SessionHistoryRewindBinding {
  const SessionHistoryRewindBinding({
    required this.history,
    this.onRewindTo,
    this.onForkFrom,
    this.busy = false,
  });

  final SeatRewindHistory history;
  final void Function(String commit)? onRewindTo;
  final void Function(String commit)? onForkFrom;
  final bool busy;
}

/// Loads later-checkpoint ghosts and wires rewind/fork around a history thread.
class SessionHistoryRewindHost extends StatefulWidget {
  const SessionHistoryRewindHost({
    required this.session,
    required this.workspace,
    required this.memberId,
    required this.liveMessages,
    required this.builder,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String memberId;
  final List<AiMessage> liveMessages;
  final Widget Function(
    BuildContext context,
    SessionHistoryRewindBinding binding,
  )
  builder;

  @override
  State<SessionHistoryRewindHost> createState() =>
      _SessionHistoryRewindHostState();
}

class _SessionHistoryRewindHostState extends State<SessionHistoryRewindHost> {
  SeatRewindHistory _history = const SeatRewindHistory.empty();
  var _allowed = false;
  var _started = false;
  var _busy = false;
  Object? _liveToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reload();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryRewindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.memberId != widget.memberId ||
        !identical(oldWidget.liveMessages, widget.liveMessages)) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final cubit = context.read<ChatCubit>();
    final token = widget.liveMessages;
    _liveToken = token;
    final allowed = cubit.rewindActionsAllowed(
      widget.session,
      widget.memberId,
    );
    var history = const SeatRewindHistory.empty();
    if (allowed) {
      try {
        history = await cubit.loadSeatRewindHistory(
          session: widget.session,
          memberId: widget.memberId,
          live: widget.liveMessages,
        );
      } on Object catch (error, stackTrace) {
        appLogger.e(
          '[rewind] load later checkpoints failed '
          'session=${widget.session.sessionId}: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (!mounted || !identical(_liveToken, token)) return;
    setState(() {
      _allowed = allowed;
      _history = history;
    });
  }

  Future<void> _onRewindTo(String commit) async {
    setState(() => _busy = true);
    try {
      await context.read<ChatCubit>().rewindSeatTo(
        sessionId: widget.session.sessionId,
        memberId: widget.memberId,
        commit: commit,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] rewindSeatTo failed session=${widget.session.sessionId}: '
        '$error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.sessionRewindFailed,
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onForkFrom(String commit) async {
    setState(() => _busy = true);
    try {
      final created = await context.read<ChatCubit>().forkSeatFrom(
        sessionId: widget.session.sessionId,
        memberId: widget.memberId,
        commit: commit,
      );
      if (created == null || !mounted) return;
      await openWorkspaceSessionTab(
        context,
        widget.workspace,
        created,
        connectImmediatelyOverride: true,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] forkSeatFrom failed session=${widget.session.sessionId}: '
        '$error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.sessionForkFailed,
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      SessionHistoryRewindBinding(
        history: _history,
        onRewindTo: _allowed ? _onRewindTo : null,
        onForkFrom: _allowed ? _onForkFrom : null,
        busy: _busy,
      ),
    );
  }
}
