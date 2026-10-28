import 'package:collection/collection.dart';

import 'vault_entry.dart';

class VaultDocument {
  const VaultDocument({this.version = 1, this.entries = const []});

  factory VaultDocument.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 1;
    if (version != 1) {
      throw const FormatException('Unsupported vault document version');
    }
    final rawEntries = json['entries'];
    return VaultDocument(
      version: version,
      entries: rawEntries is List
          ? [
              for (final raw in rawEntries)
                if (raw is Map)
                  VaultEntry.fromJson(Map<String, Object?>.from(raw)),
            ]
          : const [],
    );
  }

  final int version;
  final List<VaultEntry> entries;

  Map<String, Object?> toJson() => {
    'version': version,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  VaultDocument copyWith({List<VaultEntry>? entries}) =>
      VaultDocument(version: version, entries: entries ?? this.entries);

  @override
  bool operator ==(Object other) =>
      other is VaultDocument &&
      other.version == version &&
      const ListEquality<VaultEntry>().equals(other.entries, entries);

  @override
  int get hashCode =>
      Object.hash(version, const ListEquality<VaultEntry>().hash(entries));
}
