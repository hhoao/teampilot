import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/stop_idle_hook.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  const idle = MemberBusIdleEndpoint(url: 'http://127.0.0.1:54321/idle');
  const remoteIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:54321/idle',
    token: 'sess-tok',
  );

  test('idle script POSTs /idle and exits 2 on decision:block', () {
    final s = flashskyaiStopIdleScript(memberId: 'team-lead', idle: idle);
    expect(s, contains("X-Member: team-lead"));
    expect(s, contains('http://127.0.0.1:54321/idle'));
    expect(s, contains('"decision":"block"'));
    expect(s, contains('exit 2'));
    expect(s, contains(TeammateBusMcpHandler.stopRedirectReason));
  });

  test('idle script includes bus token for remote endpoints', () {
    final s = flashskyaiStopIdleScript(memberId: 'worker-1', idle: remoteIdle);
    expect(s, contains('X-Bus-Token: sess-tok'));
  });

  test('mergeFlashskyaiStopIdleHook installs command hook once', () {
    final once = mergeFlashskyaiStopIdleHook(const {}, '/tmp/idle.sh');
    final twice = mergeFlashskyaiStopIdleHook(once, '/tmp/idle.sh');
    final stop = (twice['hooks'] as Map)['Stop'] as List;
    expect(stop, hasLength(1));
    final hooks = (stop.single as Map)['hooks'] as List;
    final hook = hooks.single as Map;
    expect(hook['type'], 'command');
    expect(hook['command'], "bash '/tmp/idle.sh'");
  });
}
