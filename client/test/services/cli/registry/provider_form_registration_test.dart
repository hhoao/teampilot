import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_catalog_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_form_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every provider catalog CLI exposes ProviderFormCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.withCapability<ProviderCatalogCapability>()) {
      final cap = registry.capability<ProviderFormCapability>(def.id);
      expect(
        cap,
        isNotNull,
        reason: '${def.id.value} missing ProviderFormCapability',
      );
      expect(cap!.presets, isNotEmpty);
    }
  });
}
