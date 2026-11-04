import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../pages/home_workspace/workspace/workspace_session_actions.dart';
import '../../services/chat/rewind/seat_branches.dart';
import '../../utils/logging/logger.dart';
import '../../widgets/app_toast/app_toast.dart';

final class SessionHistoryRewindBinding {
  const SessionHistoryRewindBinding({
    required this.branches,
    this.onSwitchVersion,
    this.onForkFrom,
    this.onEditUserMessage,
    this.busy = false,
    this.holdTranscript = false,
    this.optimisticEdit,
    this.onOptimisticLanded,
  });

  final SeatBranches branches;
  final void Function(String commit)? onSwitchVersion;
  final void Function(String commit)? onForkFrom;
  final Future<bool> Function(String messageId, String text)? onEditUserMessage;
  final bool busy;

  /// Keeps the old transcript on screen while an edit restores and resends.
  final bool holdTranscript;

  /// Host-owned so a thread rebuild cannot drop the optimistic bubble.
  final PendingBranchEdit? optimisticEdit;

  /// Called when the runtime finally publishes the resent prompt.
  final VoidCallback? onOptimisticLanded;
}

/// Loads a seat's checkpoints and wires rewind/fork around a history thread.
class SessionHistoryRewindHost extends StatefulWidget {
  const SessionHistoryRewindHost({
    required this.session,
    required this.workspace,
    required this.memberId,
    required this.builder,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String memberId;
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
  SeatBranches _branches = const SeatBranches.empty();
  var _allowed = false;
  var _started = false;
  var _busy = false;
  var _editing = false;
  PendingBranchEdit? _seenPendingEdit;
  var _reloadSerial = 0;
  var _seenGeneration = 0;
  ChatCubit? _cubit;
  StreamSubscription<ChatState>? _generationSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<ChatCubit>();
    if (_started && identical(_cubit, cubit)) return;
    if (_started) unawaited(_generationSub?.cancel());
    _started = true;
    _cubit = cubit;
    _seenGeneration = cubit.state.rewindHistoryGeneration;
    _seenPendingEdit = cubit.state.pendingBranchEdits[widget.session.sessionId];
    _generationSub = cubit.stream.listen(_onCubitState);
    _reload();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryRewindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.memberId != widget.memberId) {
      _reload();
    }
  }

  @override
  void dispose() {
    unawaited(_generationSub?.cancel());
    super.dispose();
  }

  void _onCubitState(ChatState next) {
    if (!mounted) return;
    final pending = next.pendingBranchEdits[widget.session.sessionId];
    if (!identical(pending, _seenPendingEdit)) {
      _seenPendingEdit = pending;
      if (mounted) setState(() {});
    }
    if (next.rewindHistoryGeneration == _seenGeneration) return;
    _seenGeneration = next.rewindHistoryGeneration;
    _reload();
  }

  Future<void> _reload() async {
    final cubit = _cubit;
    if (cubit == null || !mounted) return;
    final serial = ++_reloadSerial;
    final allowed = cubit.rewindActionsAllowed(widget.session, widget.memberId);
    var branches = const SeatBranches.empty();
    if (allowed) {
      try {
        branches = await cubit.loadSeatBranches(
          session: widget.session,
          memberId: widget.memberId,
        );
      } on Object catch (error, stackTrace) {
        appLogger.e(
          '[rewind] load checkpoints failed '
          'session=${widget.session.sessionId}: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (!mounted || serial != _reloadSerial) return;
    setState(() {
      _allowed = allowed;
      _branches = branches;
    });
  }

  Future<void> _onSwitchVersion(String commit) async {
    // A second tap can land before the disabled bar rebuilds.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cubit!.switchSeatVersion(
        sessionId: widget.session.sessionId,
        memberId: widget.memberId,
        commit: commit,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] switchSeatVersion failed session=${widget.session.sessionId}: '
        '$error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.branchSwitchFailed,
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _editing = false;
        });
      }
    }
  }

  Future<void> _onForkFrom(String commit) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final created = await _cubit!.forkSeatFrom(
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

  /// Returns true when the edited turn was accepted; false keeps the editor
  /// open with the draft so the author can retry.
  void _onOptimisticLanded() {
    appLogger.d('[branch-edit] new prompt landed');
    context.read<ChatCubit>().clearPendingBranchEdit(widget.session.sessionId);
  }

  Future<bool> _onEditUserMessage(String messageId, String text) async {
    appLogger.d('[branch-edit] host begin busy=$_busy message=$messageId');
    if (_busy) return false;
    setState(() {
      _busy = true;
      _editing = true;
    });
    try {
      await _cubit!.editSeatTurn(
        sessionId: widget.session.sessionId,
        memberId: widget.memberId,
        userMessageId: messageId,
        text: text,
      );
      appLogger.d('[branch-edit] host end ok=true');
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] editSeatTurn failed session=${widget.session.sessionId}: '
        '$error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.branchEditFailed,
          variant: TpToastVariant.error,
        );
      }
      appLogger.d('[branch-edit] host end ok=false');
      if (mounted) {
        context.read<ChatCubit>().clearPendingBranchEdit(
          widget.session.sessionId,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _editing = false;
        });
      }
      appLogger.d('[branch-edit] host released');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      SessionHistoryRewindBinding(
        branches: _branches,
        onSwitchVersion: _allowed ? _onSwitchVersion : null,
        onForkFrom: _allowed ? _onForkFrom : null,
        onEditUserMessage: _allowed ? _onEditUserMessage : null,
        busy: _busy,
        holdTranscript: _editing,
        optimisticEdit: context
            .read<ChatCubit>()
            .state
            .pendingBranchEdits[widget.session.sessionId],
        onOptimisticLanded: _onOptimisticLanded,
      ),
    );
  }
}
