import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/connect/member_lifecycle_connect_gate.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_gateway_port.dart';

void main() {
  group('lifecycle gate reason helpers', () {
    test('manifest bus overlay use per-member retry', () {
      for (final reason in ['manifest', 'bus', 'overlay']) {
        expect(lifecycleGateReasonNeedsMemberRetry(reason), isTrue);
        expect(lifecycleGateReasonIsTransient(reason), isTrue);
      }
    });

    test('auth is not transient', () {
      expect(lifecycleGateReasonIsTransient('auth'), isFalse);
      expect(lifecycleGateReasonNeedsMemberRetry('auth'), isFalse);
    });
  });

  test('mixed team defers when teammate bus is not installed', () async {
    const member = TeamMemberConfig(id: 'm1', name: 'Member');
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      members: [member],
    );
    final session = AppSession(
      sessionId: 'sess',
      workspaceId: 'ws',
      sessionTeam: team.id,
      createdAt: 1,
    );
    final gate = MemberLifecycleConnectGate(
      cliRegistry: CliToolRegistry(),
      teammateBusMcpGateway: _UnregisteredGateway(),
      resolvePaths: (_, __) async => throw StateError('not reached'),
      memberWorkDirs: (_, __) => (workingDirectory: '/', addDirs: const []),
      launchWorkTarget: (_, {String? memberId}) => RuntimeTarget.local(),
      globalPresets: () => const [],
    );

    final outcome = await gate.evaluate(
      team: team,
      member: member,
      session: session,
      teamBusInstalled: false,
    );

    expect(outcome, isA<LifecycleConnectGateDeferred>());
    expect((outcome as LifecycleConnectGateDeferred).reason, 'bus');
  });
}

class _UnregisteredGateway implements TeammateBusMcpGatewayPort {
  @override
  bool isSessionRegistered(String sessionId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
