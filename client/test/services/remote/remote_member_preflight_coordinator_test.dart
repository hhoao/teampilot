import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/remote/remote_member_preflight_coordinator.dart';
import 'package:teampilot/services/remote/remote_preflight_service.dart';

import '../../support/test_runtime_context.dart';

void main() {
  RemoteMemberPreflightCoordinator coordinator({
    required RuntimeTarget home,
    required List<String> calls,
    bool optIn = false,
  }) =>
      RemoteMemberPreflightCoordinator(
        preflight: RemotePreflightService(
          connect: (t) async {
            calls.add('prepare:${t.id}');
            return testRuntimeContext('/remote');
          },
          ensureCli: ({required target, required cli}) async =>
              '/usr/bin/${cli.value}',
          materialize: ({
            required target,
            required workContext,
            required cli,
            required workspaceId,
            required optInCredentials,
          }) async {},
          bindBus: ({required target, required cli, required memberId}) async =>
              null,
        ),
        homeTarget: () => home,
        isCredentialOptIn: (_) async => optIn,
      );

  test('off-home ssh member → preflight runs and yields the remote CLI path',
      () async {
    final calls = <String>[];
    final c = coordinator(home: RuntimeTarget.local(), calls: calls);
    final result = await c.prepareIfOffHome(
      memberTarget: RuntimeTarget.ssh('p2', label: 'work'),
      cli: CliTool.claude,
      workspaceId: 'w1',
      memberId: 'm1',
    );
    expect(result, isNotNull);
    expect(result!.remoteCliPath, '/usr/bin/claude');
    expect(calls, ['prepare:ssh:p2']);
  });

  test('home-local member → no preflight (zero change)', () async {
    final calls = <String>[];
    final c = coordinator(home: RuntimeTarget.local(), calls: calls);
    final result = await c.prepareIfOffHome(
      memberTarget: RuntimeTarget.local(),
      cli: CliTool.claude,
      workspaceId: 'w1',
      memberId: 'm1',
    );
    expect(result, isNull);
    expect(calls, isEmpty);
  });

  test('home-ssh member (same machine as home) → no preflight', () async {
    final calls = <String>[];
    final home = RuntimeTarget.ssh('home', label: 'home');
    final c = coordinator(home: home, calls: calls);
    final result = await c.prepareIfOffHome(
      memberTarget: RuntimeTarget.ssh('home', label: 'home'),
      cli: CliTool.claude,
      workspaceId: 'w1',
      memberId: 'm1',
    );
    expect(result, isNull);
    expect(calls, isEmpty);
  });
}
