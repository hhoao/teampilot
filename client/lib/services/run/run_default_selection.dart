import '../../models/run/launch_configuration.dart';
import 'launch_config_store.dart';

/// Picks the Run toolbar default selection key.
///
/// Order: persisted config/compound hit → persisted path+id rematch (when the
/// owning folder's `targetId` drifted) → first configuration → first compound.
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

    // The exact key missed: the folder likely moved to another machine, which
    // changes `targetId` and therefore the `targetId|path|id` selection key.
    // Re-anchor on the path + entry id the user actually chose.
    final anchor = _parseSelectionKey(key);
    if (anchor != null) {
      for (final config in configurations) {
        if (config.owner.path == anchor.path &&
            config.configuration.id == anchor.tail) {
          return config.selectionKey;
        }
      }
      for (final compound in compounds) {
        if (compound.owner.path == anchor.path &&
            'compound:${compound.compoundId}' == anchor.tail) {
          return compound.selectionKey;
        }
      }
    }
  }
  if (configurations.isNotEmpty) return configurations.first.selectionKey;
  if (compounds.isNotEmpty) return compounds.first.selectionKey;
  return null;
}

/// Splits `targetId|path|tail` into its stable parts.
///
/// `path` may itself contain `|`, so only the first segment (`targetId`) and the
/// last segment (config id / `compound:<id>`) are fixed; everything between is
/// the path. Returns null when the key is malformed or has an empty id.
({String path, String tail})? _parseSelectionKey(String key) {
  final segments = key.split('|');
  if (segments.length < 3) return null;
  final tail = segments.last;
  if (tail.isEmpty) return null;
  final path = segments.sublist(1, segments.length - 1).join('|');
  if (path.isEmpty) return null;
  return (path: path, tail: tail);
}
