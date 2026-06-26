import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/config_profile/bus_idle_stop_hook.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  const idle = MemberBusIdleEndpoint(url: 'http://127.0.0.1:12345/idle');
  const remoteIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:54321/idle',
    token: 'sess-tok',
  );
  const memberId = 'member-a';

  test('mergeStopIdleHook adds http Stop hook with X-Member header', () {
    final merged = mergeStopIdleHook(const {}, memberId, idle);
    final stop = merged['hooks']! as Map;
    final entries = stop['Stop']! as List;
    expect(entries, hasLength(1));
    final hooks = (entries.first as Map)['hooks']! as List;
    expect(hooks.first, {
      'type': 'http',
      'url': idle.url,
      'headers': {'X-Member': memberId},
    });
  });

  test('mergeStopIdleHook adds X-Bus-Token for remote idle endpoints', () {
    final merged = mergeStopIdleHook(const {}, memberId, remoteIdle);
    final hooks =
        (((merged['hooks'] as Map)['Stop'] as List).first as Map)['hooks']
            as List;
    final headers = (hooks.first as Map)['headers'] as Map;
    expect(headers[teammateBusTokenHeader], 'sess-tok');
  });

  test('mergeStopIdleHook is idempotent for same idle url', () {
    final once = mergeStopIdleHook(const {}, memberId, idle);
    final twice = mergeStopIdleHook(once, memberId, idle);
    final stop = twice['hooks']! as Map;
    final entries = stop['Stop']! as List;
    expect(entries, hasLength(1));
  });
}
