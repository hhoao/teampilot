import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/session/member_acp_stamp.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  List<SessionMemberBinding> stamp({
    required List<SessionMemberBinding> members,
    required Map<String, String> targets,
    bool? isAndroidOverride,
  }) => stampMemberAcp(
    members: members,
    memberTargets: targets,
    seedClaudeMemberAcp: false,
    seedCodexMemberAcp: false,
    isAndroidOverride: isAndroidOverride,
  );

  // `CliToolRegistry.builtIn()` lazily installs the built-in CLIs (including
  // Qoder's ACP-only transport), so no per-test registry install is needed.
  test('qoder is registered ACP-only', () {
    final registry = CliToolRegistry.builtIn();
    expect(registry.launchesAcpOnly(CliTool.qoder), isTrue);
    final transport = registry.capability<CliTransportCapability>(
      CliTool.qoder,
    );
    expect(transport?.supported, {CliTransport.acp});
  });

  test('local mixed qoder seat is stamped ACP without a preference', () {
    final stamped = stamp(
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'r1',
          taskId: 't1',
          cli: CliTool.qoder,
        ),
      ],
      targets: const {'r1': 'local'},
      isAndroidOverride: false,
    );
    expect(stamped.single.acp, isTrue);
  });

  test('android qoder seat stays PTY', () {
    final stamped = stamp(
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'r1',
          taskId: 't1',
          cli: CliTool.qoder,
        ),
      ],
      targets: const {'r1': 'local'},
      isAndroidOverride: true,
    );
    expect(stamped.single.acp, isFalse);
  });

  test('qoder seat without a placement binding stays PTY', () {
    final stamped = stamp(
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'r1',
          taskId: 't1',
          cli: CliTool.qoder,
        ),
      ],
      targets: const {},
      isAndroidOverride: false,
    );
    expect(stamped.single.acp, isFalse);
  });

  test('ssh qoder seat is stamped ACP', () {
    final stamped = stamp(
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'r1',
          taskId: 't1',
          cli: CliTool.qoder,
        ),
      ],
      targets: const {'r1': 'ssh:prod'},
      isAndroidOverride: false,
    );
    expect(stamped.single.acp, isTrue);
  });

  test('mixed qoder/codebuddy/claude team stamps only ACP-only seats', () {
    final stamped = stamp(
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'r1',
          taskId: 't1',
          cli: CliTool.qoder,
        ),
        SessionMemberBinding(
          rosterMemberId: 'r2',
          taskId: 't2',
          cli: CliTool.codebuddy,
        ),
        SessionMemberBinding(
          rosterMemberId: 'r3',
          taskId: 't3',
          cli: CliTool.claude,
        ),
      ],
      targets: const {'r1': 'local', 'r2': 'local', 'r3': 'local'},
      isAndroidOverride: false,
    );
    expect(stamped.map((m) => m.acp), [true, true, false]);
  });
}
