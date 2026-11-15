import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_proxy_install.dart';
import 'package:teampilot/services/acp/acp_proxy_route.dart';
import 'package:teampilot/services/cli/installer_types.dart';

void main() {
  const hash =
      '0ac627d599cd7ebae39f92e947c41ec51c57d4c68b0ea6768f1a38f5987b29b7';

  test('pinned version matches the proxy package', () {
    final source = File(
      'packages/acp_proxy/lib/src/version.dart',
    ).readAsStringSync();
    expect(
      source,
      contains("const acpProxyVersion = '$acpProxyPinnedVersion'"),
    );
    expect(acpProxyPinnedVersion, '0.1.0');
  });

  test('install script pins x86_64 and refuses an unpinned aarch64', () {
    final script = buildAcpProxyInstallScript(
      cliIds: const ['claude', 'codex'],
    );

    expect(script, contains(hash));
    expect(
      script,
      contains(
        'https://github.com/hhoao/teampilot/releases/download/'
        'acp-proxy-v0.1.0/teampilot-acp-proxy-linux-x86_64',
      ),
    );
    expect(script, contains("checksum is not pinned for aarch64"));
    expect(script, isNot(contains('teampilot-acp-proxy-linux-aarch64')));
    expect(script, contains('unsupported architecture'));
    expect(script, contains('--detach'));
    expect(script, contains("--cli 'claude'"));
    expect(script, contains("--cli 'codex'"));
    expect(script, contains('curl'));
    expect(script, isNot(contains('wget')));
  });

  test('update checks the listener before signaling the pid file', () {
    final script = buildAcpProxyUpdateScript(cliIds: const ['claude']);
    final listener = script.indexOf('port listener');
    final kill = script.indexOf('kill -TERM');

    expect(listener, greaterThanOrEqualTo(0));
    expect(kill, greaterThan(listener));
    expect(script, contains('is not acp-proxy.pid'));
  });

  test('remove deletes the proxy directory and the address file', () {
    final script = buildAcpProxyRemoveScript();

    expect(script, contains('rm -rf "\$root/acp-proxy"'));
    expect(script, contains('rm -f "\$root/acp-proxy.json"'));
    expect(script, contains('kill -TERM'));
  });

  test('start does not download', () {
    final script = buildAcpProxyStartScript(cliIds: const ['gemini']);

    expect(script, contains('--detach'));
    expect(script, contains("--cli 'gemini'"));
    expect(script, isNot(contains('curl')));
    expect(script, contains('acp proxy binary is missing'));
  });

  test('unsafe or empty cli ids are rejected', () {
    expect(
      () => buildAcpProxyInstallScript(cliIds: const ['bad id']),
      throwsFormatException,
    );
    expect(
      () => buildAcpProxyStartScript(cliIds: const []),
      throwsArgumentError,
    );
  });

  test('a non-zero remote exit is a failed install result', () async {
    final installer = AcpProxyRemoteInstaller(cliIds: const ['claude']);
    final phases = <CliInstallPhase>[];

    final result = await installer.run(
      AcpProxyRemoteAction.install,
      (_) async =>
          const CliInstallerCommandResult(exitCode: 1, stderr: 'curl failed'),
      report: phases.add,
    );

    expect(result.success, isFalse);
    expect(result.message, 'curl failed');
    expect(phases, [CliInstallPhase.downloading]);
  });

  test('card action follows install, update, start, ready', () {
    expect(
      acpProxyCardAction(
        binaryPresent: false,
        advertisedVersion: null,
        pinnedVersion: acpProxyPinnedVersion,
        pidListening: false,
      ),
      AcpProxyCardAction.install,
    );
    expect(
      acpProxyCardAction(
        binaryPresent: true,
        advertisedVersion: '0.0.9',
        pinnedVersion: acpProxyPinnedVersion,
        pidListening: true,
      ),
      AcpProxyCardAction.update,
    );
    expect(
      acpProxyCardAction(
        binaryPresent: true,
        advertisedVersion: '9.0.0',
        pinnedVersion: acpProxyPinnedVersion,
        pidListening: true,
      ),
      AcpProxyCardAction.update,
    );
    expect(
      acpProxyCardAction(
        binaryPresent: true,
        advertisedVersion: acpProxyPinnedVersion,
        pinnedVersion: acpProxyPinnedVersion,
        pidListening: false,
      ),
      AcpProxyCardAction.start,
    );
    expect(
      acpProxyCardAction(
        binaryPresent: true,
        advertisedVersion: acpProxyPinnedVersion,
        pinnedVersion: acpProxyPinnedVersion,
        pidListening: true,
      ),
      AcpProxyCardAction.ready,
    );
  });

  test('an unreadable advertisement asks for an update', () {
    const snapshot = AcpProxyProbeSnapshot(
      binaryPresent: true,
      pidFile: '',
      advertisementJson: '{',
      tcpTable: '',
      advertisementFdLinks: [],
      pidFileFdLinks: [],
    );

    expect(acpProxyCardActionForProbe(snapshot), AcpProxyCardAction.update);
  });
}
