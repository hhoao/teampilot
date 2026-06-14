import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/resource_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/resource_kind.dart';

void main() {
  // CliToolRegistry.builtIn() exists and calls registerBuiltInCliTools internally.
  CliToolRegistry buildRegistry() => CliToolRegistry.builtIn();

  test('every launchable CLI exposes a ResourceCapability supporting skills', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      final cap = registry.capability<ResourceCapability>(cli);
      expect(cap, isNotNull, reason: '$cli must expose ResourceCapability');
      expect(cap!.supportedKinds, contains(ResourceKind.skill));
    }
  });

  test('opencode uses "skill" subdir; others use "skills"', () {
    final registry = buildRegistry();
    expect(
      registry.capability<ResourceCapability>(CliTool.opencode)!
          .subdirFor(ResourceKind.skill),
      'skill',
    );
    expect(
      registry.capability<ResourceCapability>(CliTool.flashskyai)!
          .subdirFor(ResourceKind.skill),
      'skills',
    );
  });
}
