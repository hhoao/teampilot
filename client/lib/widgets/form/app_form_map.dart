// Adapted from flutter-shadcn-ui MapExtensions (form value nesting helpers).

/// Nested-map helpers used by [AppForm] value aggregation.
extension AppFormMapExtensions on Map<String, dynamic> {
  /// Converts flat separator-based keys into a nested map.
  Map<String, dynamic> toNestedMap({String separator = '.'}) {
    assert(separator.isNotEmpty, 'Separator cannot be empty');
    final result = <String, dynamic>{};

    for (final entry in entries) {
      final keys = entry.key.split(separator);
      if (keys.length == 1) {
        result[entry.key] = entry.value;
        continue;
      }
      var current = result;
      for (var i = 0; i < keys.length - 1; i++) {
        final key = keys[i];
        if (current[key] is! Map<String, dynamic>) {
          current[key] = <String, dynamic>{};
        }
        current = current[key]! as Map<String, dynamic>;
      }
      current[keys.last] = entry.value;
    }

    return result;
  }

  /// Reads a nested value via a separator path.
  dynamic getByPath(String path, {String separator = '.'}) {
    assert(separator.isNotEmpty, 'Separator cannot be empty');
    final keys = path.split(separator);
    dynamic current = this;
    for (final key in keys) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Deep-merges [other] into this map (nested maps recurse; other values replace).
  Map<String, dynamic> deepMerge(Map<String, dynamic> other) {
    final result = Map<String, dynamic>.from(this);
    for (final entry in other.entries) {
      if (result[entry.key] is Map && entry.value is Map) {
        final existing = Map<String, dynamic>.from(result[entry.key]! as Map);
        final incoming = Map<String, dynamic>.from(entry.value as Map);
        result[entry.key] = existing.deepMerge(incoming);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Deep-copies nested maps (lists/sets copied shallowly as new collections).
  Map<String, dynamic> deepCopy() {
    final copy = <String, dynamic>{};
    for (final entry in entries) {
      final value = entry.value;
      if (value is Map) {
        copy[entry.key] = Map<String, dynamic>.from(
          value.map((k, v) => MapEntry(k.toString(), v)),
        ).deepCopy();
      } else if (value is List) {
        copy[entry.key] = List<dynamic>.from(value);
      } else if (value is Set) {
        copy[entry.key] = Set<dynamic>.from(value);
      } else {
        copy[entry.key] = value;
      }
    }
    return copy;
  }
}
