import '../../models/run/launch_configuration.dart';
import 'launch_config_store.dart';

/// Picks the Run toolbar default selection key.
///
/// Order: persisted config/compound hit → first configuration → first compound.
/// Recommendations are intentionally not considered.
String? resolveRunDefaultSelection({
  required String? persistedKey,
  required List<OwnedLaunchConfiguration> configurations,
  required List<OwnedLaunchCompound> compounds,
}) {
  final key = persistedKey?.trim();
  if (key != null && key.isNotEmpty) {
    for (final config in configurations) {
      if (config.selectionKey == key) return key;
    }
    for (final compound in compounds) {
      if (compound.selectionKey == key) return key;
    }
  }
  if (configurations.isNotEmpty) return configurations.first.selectionKey;
  if (compounds.isNotEmpty) return compounds.first.selectionKey;
  return null;
}
