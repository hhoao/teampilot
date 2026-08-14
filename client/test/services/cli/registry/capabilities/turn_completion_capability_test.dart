import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/team_behavior_capability.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('cursor declares stop done + PTY fallback + doorbell push', () {
    final cap = registry.capability<TeamBehaviorCapability>(CliTool.cursor);
    expect(cap, isNotNull);
    expect(cap!.doneEventNames, {'stop'});
    expect(cap.requiresPtyFallback, isTrue);
    expect(cap.usesDoorbellPush, isTrue);
  });

  test('claude declares Stop/StopFailure done, no fallback, no push', () {
    final cap = registry.capability<TeamBehaviorCapability>(CliTool.claude);
    expect(cap, isNotNull);
    expect(cap!.doneEventNames, {'Stop', 'StopFailure'});
    expect(cap.requiresPtyFallback, isFalse);
    expect(cap.usesDoorbellPush, isFalse);
  });

  test('opencode declares session.idle done, no fallback', () {
    final cap = registry.capability<TeamBehaviorCapability>(CliTool.opencode);
    expect(cap, isNotNull);
    expect(cap!.doneEventNames, {'session.idle'});
    expect(cap.requiresPtyFallback, isFalse);
  });

  test('codex and flashskyai declare Stop/StopFailure done, no fallback', () {
    for (final cli in [CliTool.codex, CliTool.flashskyai]) {
      final cap = registry.capability<TeamBehaviorCapability>(cli);
      expect(cap, isNotNull);
      expect(cap!.doneEventNames, {'Stop', 'StopFailure'});
      expect(cap.requiresPtyFallback, isFalse);
      expect(cap.usesDoorbellPush, isFalse);
    }
  });
}
