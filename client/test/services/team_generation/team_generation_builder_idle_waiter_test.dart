import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/team_generation/team_generation_builder_idle_waiter.dart';
import 'package:teampilot/services/team_generation/team_generation_session_port.dart';

class _FakePort implements TeamGenerationSessionPort {
  final _controllers = <String, StreamController<PortActivity>>{};

  void emit(String sessionId, bool ready) {
    _controllers
        .putIfAbsent(sessionId, StreamController<PortActivity>.broadcast)
        .add(PortActivity(sessionId: sessionId, readyToChat: ready));
  }

  @override
  Future<SessionPortOpenResult> createBuilder({
    required Workspace workspace,
    required SimpleLaunchIdentity identity,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String workflowId,
    required String fixedSessionId,
    required String expertKey,
    String emptyDisplayTitleFallback = 'Team Builder',
    bool preserveWorkbenchView = true,
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> createDestination({
    required Workspace workspace,
    required TeamProfile team,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String fixedSessionId,
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> open(String sessionId) async =>
      const SessionPortOpenResult(status: 'opened');

  @override
  Future<void> select(String sessionId) async {}

  @override
  Future<AppSession?> sessionById(String sessionId) async => null;

  @override
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  }) async {}

  @override
  Future<void> persistHistoryPending(
    String sessionId,
    String memberId,
    String text, {
    required String deliveryId,
  }) async {}

  @override
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  }) async => const PortDeliveryOutcome(result: 'submitted');

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async => true;

  @override
  Stream<PortActivity> activityStream(String sessionId) => _controllers
      .putIfAbsent(sessionId, StreamController<PortActivity>.broadcast)
      .stream;
}

void main() {
  test('timeout is recoverable and does not imply idle', () async {
    final port = _FakePort();
    final waiter = TeamGenerationBuilderIdleWaiter(sessionPort: port);

    final result = await waiter.wait(
      sessionId: 'builder',
      quietWindow: const Duration(milliseconds: 750),
      timeout: const Duration(milliseconds: 100),
    );

    expect(result, TeamGenerationBuilderIdleResult.timeout);
  });

  test('idle result after ready and a quiet window', () async {
    final port = _FakePort();
    final waiter = TeamGenerationBuilderIdleWaiter(sessionPort: port);

    final waiting = waiter.wait(
      sessionId: 'builder',
      quietWindow: const Duration(milliseconds: 100),
      timeout: const Duration(seconds: 5),
    );
    port.emit('builder', true);
    // Restart the timer once mid-window; the second quiet window completes.
    Future<void>.delayed(const Duration(milliseconds: 40), () {
      port.emit('builder', false);
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        port.emit('builder', true);
      });
    });

    expect(await waiting, TeamGenerationBuilderIdleResult.idle);
  });
}
