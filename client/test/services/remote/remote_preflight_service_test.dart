import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/remote/remote_preflight_service.dart';

import '../../support/test_runtime_context.dart';

void main() {
  final target = RuntimeTarget.ssh('p1', label: 'work');

  test('runs steps in order: connect -> locate/install -> materialize -> bus-bind',
      () async {
    final order = <String>[];
    final svc = RemotePreflightService(
      connect: (t) async {
        order.add('connect');
        return testRuntimeContext('/remote');
      },
      ensureCli: ({required target, required cli}) async {
        order.add('locate');
        return '/usr/bin/${cli.value}';
      },
      materialize: ({
        required target,
        required workContext,
        required cli,
        required workspaceId,
        required optInCredentials,
      }) async =>
          order.add('materialize'),
      bindBus: ({required target, required cli, required memberId}) async {
        order.add('bind');
        return null;
      },
    );

    final result = await svc.prepare(
      target: target,
      cli: CliTool.claude,
      workspaceId: 'w1',
      memberId: 'm1',
      optInCredentials: false,
    );

    expect(order, ['connect', 'locate', 'materialize', 'bind']);
    expect(result.remoteCliPath, '/usr/bin/claude');
  });

  test('connect failure short-circuits with a clear target-unavailable error',
      () async {
    final order = <String>[];
    final svc = RemotePreflightService(
      connect: (t) async => throw StateError('no route to host'),
      ensureCli: ({required target, required cli}) async {
        order.add('locate');
        return '';
      },
      materialize: ({
        required target,
        required workContext,
        required cli,
        required workspaceId,
        required optInCredentials,
      }) async =>
          order.add('materialize'),
      bindBus: ({required target, required cli, required memberId}) async =>
          null,
    );

    await expectLater(
      svc.prepare(
        target: target,
        cli: CliTool.claude,
        workspaceId: 'w1',
        memberId: 'm1',
        optInCredentials: false,
      ),
      throwsA(isA<PreflightTargetUnavailableException>()),
    );
    expect(order, isEmpty); // nothing past connect ran
  });

  test('locate/install failure surfaces, no materialize attempted', () async {
    final order = <String>[];
    final svc = RemotePreflightService(
      connect: (t) async => testRuntimeContext('/remote'),
      ensureCli: ({required target, required cli}) async =>
          throw StateError('cli not found / opt-in off'),
      materialize: ({
        required target,
        required workContext,
        required cli,
        required workspaceId,
        required optInCredentials,
      }) async =>
          order.add('materialize'),
      bindBus: ({required target, required cli, required memberId}) async =>
          null,
    );

    await expectLater(
      svc.prepare(
        target: target,
        cli: CliTool.claude,
        workspaceId: 'w1',
        memberId: 'm1',
        optInCredentials: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(order, isEmpty); // materialize never attempted
  });
}
