import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/session/launch_acp_policy.dart';

void main() {
  test('dual-transport CLI follows requested on local/ssh/termux', () {
    for (final target in ['local', 'ssh:box', 'termux:default']) {
      expect(
        resolveAcpOnTarget(
          cli: CliTool.claude,
          targetId: target,
          requested: true,
        ),
        isTrue,
        reason: target,
      );
      expect(
        resolveAcpOnTarget(
          cli: CliTool.claude,
          targetId: target,
          requested: false,
        ),
        isFalse,
        reason: target,
      );
    }
  });

  test('ACP-only CLIs are forced when the target supports ACP', () {
    for (final cli in [
      CliTool.gemini,
      CliTool.codebuddy,
      CliTool.qoder,
      CliTool.antigravity,
      CliTool.grok,
    ]) {
      expect(
        resolveAcpOnTarget(cli: cli, targetId: 'ssh:box', requested: false),
        isTrue,
        reason: cli.value,
      );
      expect(
        acpAvailabilityFor(cli: cli, targetId: 'ssh:box'),
        AcpAvailability.forced,
        reason: cli.value,
      );
    }
  });

  test('WSL has no exec channel', () {
    expect(
      acpAvailabilityFor(cli: CliTool.gemini, targetId: 'wsl:Ubuntu'),
      AcpAvailability.unsupported,
    );
    expect(
      resolveAcpOnTarget(
        cli: CliTool.claude,
        targetId: 'wsl:Ubuntu',
        requested: true,
      ),
      isFalse,
    );
  });

  test('CLI without ACP is unsupported', () {
    expect(
      resolveAcpOnTarget(
        cli: CliTool.flashskyai,
        targetId: 'local',
        requested: true,
      ),
      isFalse,
    );
    expect(
      resolveAcpOnTarget(cli: null, targetId: 'local', requested: true),
      isFalse,
    );
  });

  test('canChooseAcpTransport is true only for optional', () {
    expect(
      canChooseAcpTransport(cli: CliTool.claude, targetId: 'ssh:box'),
      isTrue,
    );
    expect(
      canChooseAcpTransport(cli: CliTool.gemini, targetId: 'ssh:box'),
      isFalse,
    );
    expect(
      canChooseAcpTransport(cli: CliTool.claude, targetId: 'wsl:Ubuntu'),
      isFalse,
    );
  });

  test('acpForcedByCli is capability-only', () {
    expect(acpForcedByCli(CliTool.gemini), isTrue);
    expect(acpForcedByCli(CliTool.antigravity), isTrue);
    expect(acpForcedByCli(CliTool.grok), isTrue);
    expect(acpForcedByCli(CliTool.claude), isFalse);
    expect(acpForcedByCli(null), isFalse);
  });
}
