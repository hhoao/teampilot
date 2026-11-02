import 'package:collection/collection.dart';

import 'vault_entry.dart';

class VaultDocument {
  const VaultDocument({
    this.version = 1,
    this.entries = const [],
    this.legacyImportVersion = 0,
  });

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
      legacyImportVersion:
          (json['legacyImportVersion'] as num?)?.toInt() ?? 0,
    );
  }

  final int version;
  final List<VaultEntry> entries;

  /// `0` until the one-shot legacy import completed a full pass.
  final int legacyImportVersion;

  Map<String, Object?> toJson() => {
    'version': version,
    if (legacyImportVersion > 0) 'legacyImportVersion': legacyImportVersion,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  VaultDocument copyWith({
    List<VaultEntry>? entries,
    int? legacyImportVersion,
  }) => VaultDocument(
    version: version,
    entries: entries ?? this.entries,
    legacyImportVersion: legacyImportVersion ?? this.legacyImportVersion,
  );

  @override
  bool operator ==(Object other) =>
      other is VaultDocument &&
      other.version == version &&
      other.legacyImportVersion == legacyImportVersion &&
      const ListEquality<VaultEntry>().equals(other.entries, entries);

  @override
  int get hashCode => Object.hash(
    version,
    legacyImportVersion,
    const ListEquality<VaultEntry>().hash(entries),
  );
}
