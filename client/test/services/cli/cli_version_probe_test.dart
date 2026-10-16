import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_version_probe.dart';

void main() {
  test('installed takes the first line of --version stdout', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        expect(exe, '/usr/bin/claude');
        expect(args, ['--version']);
        return ProcessResult(0, 0, '2.1.4 (Claude Code)\nextra\n', '');
      },
    );
    expect(await probe.installed('/usr/bin/claude'), '2.1.4');
  });

  test('installed extracts version from npm-style --version banners', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        expect(exe, '/usr/bin/codex-acp');
        return ProcessResult(0, 0, 'agentclientprotocol/codex-acp 2.2.2\n', '');
      },
    );
    expect(await probe.installed('/usr/bin/codex-acp'), '2.2.2');
  });

  test('cliVersionToken strips banners and leading v', () {
    expect(cliVersionToken('2.1.4 (Claude Code)'), '2.1.4');
    expect(cliVersionToken('agentclientprotocol/codex-acp 2.2.2'), '2.2.2');
    expect(cliVersionToken('v0.44.1'), '0.44.1');
    expect(cliVersionToken('2.2.2'), '2.2.2');
    expect(cliVersionToken('not a version'), isNull);
  });

  test('installed returns null when --version fails', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        return ProcessResult(0, 1, '', 'not found');
      },
    );
    expect(await probe.installed('/missing/claude'), isNull);
  });

  test('latestNpm returns null on failure without throwing', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        throw Exception('offline');
      },
    );
    expect(await probe.latestNpm('@anthropic-ai/claude-code'), isNull);
  });

  test('latestNpm reads npm view stdout', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        expect(exe, 'npm');
        expect(args, ['view', '@anthropic-ai/claude-code', 'version']);
        return ProcessResult(0, 0, '2.2.0\n', '');
      },
    );
    expect(await probe.latestNpm('@anthropic-ai/claude-code'), '2.2.0');
  });
}
