import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/branch_edit_controller.dart';
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
    this.onPickEditAttachments,
    required this.branchEdit,
    this.busy = false,
    this.onOptimisticLanded,
  });

  final SeatBranches branches;
  final void Function(String commit)? onSwitchVersion;
  final void Function(String commit)? onForkFrom;
  final Future<bool> Function(String messageId, String text)? onEditUserMessage;

  /// Opens the host file picker for the inline editor and returns `@` refs.
  final Future<List<String>> Function()? onPickEditAttachments;
  final bool busy;

  /// Single source of truth for pending/draft/editor state.
  final BranchEditController branchEdit;

  bool get holdTranscript => branchEdit.holdsTranscript;

  /// Called when the runtime finally publishes the resent prompt.
  final VoidCallback? onOptimisticLanded;
}

/// Loads a seat's checkpoints and wires rewind/fork around a history thread.
class SessionHistoryRewindHost extends StatefulWidget {
  const SessionHistoryRewindHost({
    required this.session,
    required this.workspace,
    required this.memberId,
    this.onPickEditAttachments,
    required this.builder,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String memberId;

  /// Opens the host file picker for the inline editor (see
  /// [SessionHistoryRewindBinding.onPickEditAttachments]).
  final Future<List<String>> Function()? onPickEditAttachments;
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
  var _reloadSerial = 0;
  var _seenGeneration = 0;
  var _seenOperationInProgress = false;
  ChatCubit? _cubit;
  BranchEditController? _branchEdit;
  StreamSubscription<ChatState>? _generationSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<ChatCubit>();
    if (_started && identical(_cubit, cubit)) return;
    if (_started) unawaited(_generationSub?.cancel());
    _started = true;
    _cubit = cubit;
    _attachBranchEdit(cubit);
    _seenGeneration =
        cubit.state.rewindHistoryGenerations[widget.session.sessionId] ?? 0;
    _seenOperationInProgress = cubit.state.rewindForkInProgress.contains(
      widget.session.sessionId,
    );
    _generationSub = cubit.stream.listen(_onCubitState);
    _reload();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryRewindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.memberId != widget.memberId) {
      final cubit = _cubit;
      if (cubit != null) {
        _attachBranchEdit(cubit);
        _seenGeneration =
            cubit.state.rewindHistoryGenerations[widget.session.sessionId] ?? 0;
        _seenOperationInProgress = cubit.state.rewindForkInProgress.contains(
          widget.session.sessionId,
        );
      }
      _reload();
    }
  }

  @override
  void dispose() {
    _branchEdit?.removeListener(_onBranchEditChanged);
    unawaited(_generationSub?.cancel());
    super.dispose();
  }

  void _attachBranchEdit(ChatCubit cubit) {
    _branchEdit?.removeListener(_onBranchEditChanged);
    _branchEdit = cubit.branchEditFor(widget.session.sessionId);
    _branchEdit!.addListener(_onBranchEditChanged);
  }

  void _onBranchEditChanged() {
    if (mounted) setState(() {});
  }

  void _onCubitState(ChatState next) {
    if (!mounted) return;
    if (next.rewindForkInProgress.contains(widget.session.sessionId) !=
        _seenOperationInProgress) {
      _seenOperationInProgress = next.rewindForkInProgress.contains(
        widget.session.sessionId,
      );
      if (mounted) setState(() {});
    }
    final generation =
        next.rewindHistoryGenerations[widget.session.sessionId] ?? 0;
    if (generation == _seenGeneration) return;
    _seenGeneration = generation;
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
        setState(() => _busy = false);
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
          message: context.l10n.session.forkFailed,
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
    _branchEdit?.markLanded();
  }

  Future<bool> _onEditUserMessage(String messageId, String text) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await _cubit!.editSeatTurn(
        sessionId: widget.session.sessionId,
        memberId: widget.memberId,
        userMessageId: messageId,
        text: text,
      );
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
      if (mounted) {
        context.read<ChatCubit>().clearPendingBranchEdit(
          widget.session.sessionId,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<ChatCubit>().state;
    final branchEdit = _branchEdit!;
    return widget.builder(
      context,
      SessionHistoryRewindBinding(
        branches: _branches,
        onSwitchVersion: _allowed ? _onSwitchVersion : null,
        onForkFrom: _allowed ? _onForkFrom : null,
        onEditUserMessage: _allowed ? _onEditUserMessage : null,
        onPickEditAttachments: _allowed ? widget.onPickEditAttachments : null,
        // Keep fork/switch/edit disabled until the optimistic prompt lands;
        // clearing _busy at send time opens a race with a second rewind.
        branchEdit: branchEdit,
        busy:
            _busy ||
            branchEdit.pending != null ||
            state.rewindForkInProgress.contains(widget.session.sessionId),
        onOptimisticLanded: _onOptimisticLanded,
      ),
    );
  }
}
