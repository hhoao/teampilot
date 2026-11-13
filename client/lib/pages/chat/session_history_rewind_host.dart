import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../pages/home_workspace/workspace/workspace_session_actions.dart';
import '../../services/chat/rewind/edit/edit_operation.dart';
import '../../services/chat/rewind/edit/seat_edit_coordinator.dart';
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
    required this.seatEdit,
    this.busy = false,
    this.onOptimisticLanded,
  });

  final SeatBranches branches;
  final void Function(String commit)? onSwitchVersion;
  final void Function(String commit)? onForkFrom;

  /// Accepts the edit and returns immediately; progress lives on [seatEdit].
  final Future<bool> Function(
    String messageId,
    String text, {
    required bool reopenEditor,
  })?
  onEditUserMessage;

  /// Opens the host file picker for the inline editor and returns `@` refs.
  final Future<List<String>> Function()? onPickEditAttachments;
  final bool busy;

  /// Single source of truth for the edit transaction, pending bubble, and
  /// editor state.
  final SeatEditCoordinator seatEdit;

  bool get holdTranscript => seatEdit.holdsTranscript;

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
  EditPhase? _seenEditPhase;
  ChatCubit? _cubit;
  SeatEditCoordinator? _seatEdit;
  StreamSubscription<ChatState>? _generationSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<ChatCubit>();
    if (_started && identical(_cubit, cubit)) return;
    if (_started) unawaited(_generationSub?.cancel());
    _started = true;
    _cubit = cubit;
    _attachSeatEdit(cubit);
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
        _attachSeatEdit(cubit);
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
    _seatEdit?.removeListener(_onSeatEditChanged);
    unawaited(_generationSub?.cancel());
    super.dispose();
  }

  void _attachSeatEdit(ChatCubit cubit) {
    _seatEdit?.removeListener(_onSeatEditChanged);
    _seatEdit = cubit.seatEditFor(widget.session.sessionId);
    _seenEditPhase = _seatEdit!.operation?.phase;
    _seatEdit!.addListener(_onSeatEditChanged);
  }

  void _onSeatEditChanged() {
    if (!mounted) return;
    final phase = _seatEdit?.operation?.phase;
    final failed = phase == EditPhase.failed && _seenEditPhase != phase;
    _seenEditPhase = phase;
    setState(() {});
    if (failed) {
      AppToast.show(
        context,
        message: context.l10n.branchEditFailed,
        variant: TpToastVariant.error,
      );
    }
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
    var primed = false;
    try {
      await cubit.prepareRewindFor(widget.session, widget.memberId);
      primed = true;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] prepareRewindFor failed '
        'session=${widget.session.sessionId}: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
    // A failed prime keeps the allowed=false path: no branches, but setState
    // still runs so the host never shows stale actions or skips the rebuild.
    final allowed =
        primed && cubit.rewindActionsAllowed(widget.session, widget.memberId);
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

  void _onOptimisticLanded() {
    _seatEdit?.markLanded();
  }

  /// Returns true as soon as the edit is accepted; the resend runs detached.
  Future<bool> _onEditUserMessage(
    String messageId,
    String text, {
    required bool reopenEditor,
  }) async {
    if (_busy) return false;
    return _seatEdit!.submit(
      messageId: messageId,
      memberId: widget.memberId,
      text: text,
      reopenEditorOnFailure: reopenEditor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<ChatCubit>().state;
    final seatEdit = _seatEdit!;
    return widget.builder(
      context,
      SessionHistoryRewindBinding(
        branches: _branches,
        onSwitchVersion: _allowed ? _onSwitchVersion : null,
        onForkFrom: _allowed ? _onForkFrom : null,
        onEditUserMessage: _allowed ? _onEditUserMessage : null,
        onPickEditAttachments: _allowed ? widget.onPickEditAttachments : null,
        // Keep fork/switch/edit disabled while an edit transaction runs.
        seatEdit: seatEdit,
        busy:
            _busy ||
            seatEdit.isActive ||
            state.rewindForkInProgress.contains(widget.session.sessionId),
        onOptimisticLanded: _onOptimisticLanded,
      ),
    );
  }
}
