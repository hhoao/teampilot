import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp.dart';

void main() {
  test('uses the separate ACP server with no CLI flags', () {
    const cap = AntigravityAcpCapability(linuxUid: false);
    expect(cap.agentExecutable('/usr/bin/agy'), 'agy_acp_server.par');
    expect(cap.launchArgCandidates('agy_acp_server.par'), [
      ['agy_acp_server.par'],
    ]);
    expect(cap.forwardSessionNewMcpServers, isFalse);
    expect(cap.authenticateMethodId, isNull);
    expect(cap.startupTimeout, const Duration(seconds: 120));
  });

  test('isolates HOME and passes the model env', () {
    const cap = AntigravityAcpCapability(
      linuxUid: false,
      model: 'gemini-3.8-flash-medium',
    );
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/sessions/s1/antigravity',
      workingDirectory: '/work',
      baseEnv: const {'PATH': '/bin'},
    );
    expect(env['HOME'], '/runtime/sessions/s1/antigravity/home');
    expect(env['USERPROFILE'], '/runtime/sessions/s1/antigravity/home');
    expect(env['GEMINI_HOME'], '/runtime/sessions/s1/antigravity/home/.gemini');
    expect(env['AGY_ACP_DEFAULT_MODEL'], 'gemini-3.8-flash-medium');
    expect(env['PATH'], '/bin');
  });

  test('production default enables the empty uid form on Linux only', () {
    const cap = AntigravityAcpCapability();
    expect(
      cap.launchArgCandidates('server'),
      Platform.isLinux
          ? [
              ['server', '--uid='],
              ['server'],
            ]
          : [
              ['server'],
            ],
    );
  });

  test('Linux adapter candidates include the empty uid form first', () {
    const cap = AntigravityAcpCapability(linuxUid: true);
    expect(cap.launchArgCandidates('server'), [
      ['server', '--uid='],
      ['server'],
    ]);
  });
}
