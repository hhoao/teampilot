part of 'chat_cubit.dart';

final class _CubitSeatProcess implements SeatProcess {
  _CubitSeatProcess(this._cubit, this._session, this._memberId);

  final ChatCubit _cubit;
  final AppSession _session;
  final String _memberId;

  @override
  bool get turnInFlight {
    final activity = _cubit.state.sessionActivities[_session.sessionId];
    return activity?.isInTurn == true ||
        activity?.isBusy == true ||
        activity?.isDelivering == true;
  }

  @override
  bool get localRuntime {
    final workTarget = _cubit._lifecycle.launchWorkTarget(
      _cubit._launchService.launchContextFor(_session),
      memberId: _session.isSimple ? null : _memberId,
    );
    return workTarget.kind == RuntimeKind.local;
  }

  @override
  Future<void> stopAndWait() async {
    if (isAcpChatSession(_session)) {
      await _cubit.discardPersonalAcpRuntime(_session.sessionId);
      return;
    }
    if (isAcpChatSeat(_session, _memberId)) {
      await _cubit.discardAcpSeat(_session.sessionId, _memberId);
      return;
    }
    final tab = _cubit._tabStore.getOpenTabBySessionId(_session.sessionId);
    final TerminalSession? shell;
    if (_session.isSimple) {
      shell = displayedPersonalResumeShell(
        sessionId: _session.sessionId,
        resumeSession: tab?.resumeSession,
        memberShells: tab?.memberShells ?? const {},
      );
      shell?.disconnect();
    } else {
      shell = tab?.memberShells[_memberId];
      _cubit.disconnectMemberShell(_session.sessionId, _memberId);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (shell != null && shell.isRunning) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Seat shell did not stop within 15s',
          const Duration(seconds: 15),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  @override
  Future<void> recordNativeSessionId(String? nativeSessionId) async {
    final id = nativeSessionId?.trim() ?? '';
    if (id.isEmpty) return;
    final repo = _cubit._sessionRepository;
    if (repo == null) return;
    final cli = _cubit._cliForRewindSeat(_session, _memberId);
    await repo.recordNativeSessionId(
      _session.sessionId,
      tool: cli.value,
      nativeId: id,
      rosterMemberId: _session.isSimple ? null : _memberId,
    );
    final AppSession updated;
    if (_session.isSimple) {
      updated = _session.withNativeSessionId(cli.value, id);
    } else {
      final binding = _session.bindingFor(_memberId);
      if (binding == null) return;
      final next = binding.withNativeSessionId(cli.value, id);
      updated = _session.copyWith(
        members: [
          for (final member in _session.members)
            if (member.rosterMemberId == _memberId) next else member,
        ],
      );
    }
    _cubit.replaceSessionSnapshot(updated);
    _cubit._tabStore
            .getOpenTabBySessionId(_session.sessionId)
            ?.persistedSession =
        updated;
  }

  @override
  Future<void> relaunch() async {
    if (_session.isSimple) {
      await _cubit.retrySessionLaunch(_session.sessionId);
      return;
    }
    await _cubit.ensureMemberTerminalForView(_session.sessionId, _memberId);
  }
}

final class _CubitForkSessionCreator implements ForkSessionCreator {
  _CubitForkSessionCreator({
    required this.cubit,
    required this.repo,
    required this.fixedSessionId,
  });

  final ChatCubit cubit;
  final SessionRepository repo;
  final String fixedSessionId;

  @override
  Future<String> createPersonal({
    required String workspaceId,
    required CliTool cli,
    required String display,
    required String? workingDirectory,
    required String? nativeSessionId,
  }) async {
    final created = await cubit._dataStore.createSession(
      workspaceId,
      repo,
      sessionTeamId: '',
      cli: cli,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
    );
    try {
      await repo.renameSession(created.sessionId, display);
      if (nativeSessionId != null && nativeSessionId.trim().isNotEmpty) {
        await repo.recordNativeSessionId(
          created.sessionId,
          tool: cli.value,
          nativeId: nativeSessionId.trim(),
        );
      }
      var next = created.copyWith(display: display);
      if (nativeSessionId != null && nativeSessionId.trim().isNotEmpty) {
        next = next.withNativeSessionId(cli.value, nativeSessionId.trim());
      }
      cubit._dataStore.markSessionDocument(next.sessionId);
      cubit._emitSnapshot(
        cubit._dataStore.appendSession(cubit.stateSnapshot(), next),
      );
      return next.sessionId;
    } catch (_) {
      try {
        await cubit.deleteSession(repo, created.sessionId);
      } on Object {
        // Keep the original create/rename/record failure.
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    await cubit.deleteSession(repo, sessionId);
  }
}
