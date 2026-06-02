import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/config_profile/bus_idle_stop_hook.dart';

void main() {
  const idleUrl = 'http://127.0.0.1:12345/idle';
  const memberId = 'member-a';

  test('mergeStopIdleHook adds http Stop hook with X-Member header', () {
    final merged = mergeStopIdleHook(const {}, memberId, idleUrl);
    final stop = merged['hooks']! as Map;
    final entries = stop['Stop']! as List;
    expect(entries, hasLength(1));
    final hooks = (entries.first as Map)['hooks']! as List;
    expect(hooks.first, {
      'type': 'http',
      'url': idleUrl,
      'headers': {'X-Member': memberId},
    });
  });

  test('mergeStopIdleHook is idempotent for same idleUrl', () {
    final once = mergeStopIdleHook(const {}, memberId, idleUrl);
    final twice = mergeStopIdleHook(once, memberId, idleUrl);
    final stop = twice['hooks']! as Map;
    final entries = stop['Stop']! as List;
    expect(entries, hasLength(1));
  });
}
