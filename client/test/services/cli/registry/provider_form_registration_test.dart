import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every provider catalog CLI exposes ProviderFormCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.withCapability<ProviderCapability>()) {
      final cap = registry.capability<ProviderCapability>(def.id);
      expect(
        cap,
        isNotNull,
        reason: '${def.id.value} missing ProviderFormCapability',
      );
      expect(cap!.presets, isNotEmpty);
    }
  });
}
