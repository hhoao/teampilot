import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

enum VaultEntryType {
  sshPassword('ssh_password'),
  sshPrivateKey('ssh_private_key'),
  apiKey('api_key'),
  login('login'),
  token('token'),
  secureNote('secure_note'),
  custom('custom');

  const VaultEntryType(this.storageValue);

  final String storageValue;

  static VaultEntryType fromStorage(Object? raw) {
    for (final type in values) {
      if (type.storageValue == raw) return type;
    }
    return VaultEntryType.custom;
  }

  List<String> get defaultFields => switch (this) {
    VaultEntryType.sshPassword => const [
      'host',
      'port',
      'username',
      'password',
    ],
    VaultEntryType.sshPrivateKey => const ['privateKey', 'passphrase'],
    VaultEntryType.apiKey => const ['provider', 'apiKey', 'baseUrl'],
    VaultEntryType.login => const ['url', 'username', 'password'],
    VaultEntryType.token => const ['token'],
    VaultEntryType.secureNote => const ['note'],
    VaultEntryType.custom => const [],
  };

  Set<String> get secretFields => switch (this) {
    VaultEntryType.sshPassword => const {'password', 'relayGrant'},
    VaultEntryType.sshPrivateKey => const {
      'privateKey',
      'passphrase',
      'relayGrant',
    },
    VaultEntryType.apiKey => const {'apiKey'},
    VaultEntryType.login => const {'password'},
    VaultEntryType.token => const {'token'},
    VaultEntryType.secureNote => const {'note'},
    VaultEntryType.custom => const {},
  };
}

@immutable
class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.type,
    required this.title,
    this.fields = const {},
    this.tags = const [],
    this.notes = '',
    this.favorite = false,
    this.revealable = true,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.extra = const {},
  });

  factory VaultEntry.fromJson(Map<String, Object?> json) {
    const known = {
      'id',
      'type',
      'title',
      'fields',
      'tags',
      'notes',
      'favorite',
      'revealable',
      'createdAt',
      'updatedAt',
    };
    final rawFields = json['fields'];
    return VaultEntry(
      id: json['id']?.toString() ?? '',
      type: VaultEntryType.fromStorage(json['type']),
      title: json['title']?.toString() ?? '',
      fields: rawFields is Map
          ? {
              for (final entry in rawFields.entries)
                entry.key.toString(): entry.value?.toString() ?? '',
            }
          : const {},
      tags:
          (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      notes: json['notes']?.toString() ?? '',
      favorite: json['favorite'] == true,
      revealable: json['revealable'] != false,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      extra: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  final String id;
  final VaultEntryType type;
  final String title;
  final Map<String, String> fields;
  final List<String> tags;
  final String notes;
  final bool favorite;
  final bool revealable;
  final int createdAt;
  final int updatedAt;
  final Map<String, Object?> extra;

  /// 私钥永远不可揭示；其余类型遵循条目标记。
  bool get revealAllowed => type != VaultEntryType.sshPrivateKey && revealable;

  bool isSecretField(String field) {
    if (type == VaultEntryType.custom) return true;
    return type.secretFields.contains(field);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.storageValue,
    'title': title,
    'fields': fields,
    'tags': tags,
    'notes': notes,
    'favorite': favorite,
    'revealable': revealable,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    ...extra,
  };

  VaultEntry copyWith({
    String? id,
    VaultEntryType? type,
    String? title,
    Map<String, String>? fields,
    List<String>? tags,
    String? notes,
    bool? favorite,
    bool? revealable,
    int? createdAt,
    int? updatedAt,
    Map<String, Object?>? extra,
  }) {
    return VaultEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      fields: fields ?? this.fields,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      revealable: revealable ?? this.revealable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) {
    const deep = DeepCollectionEquality();
    const list = ListEquality<String>();
    return other is VaultEntry &&
        other.id == id &&
        other.type == type &&
        other.title == title &&
        deep.equals(other.fields, fields) &&
        list.equals(other.tags, tags) &&
        other.notes == notes &&
        other.favorite == favorite &&
        other.revealable == revealable &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        deep.equals(other.extra, extra);
  }

  @override
  int get hashCode {
    const deep = DeepCollectionEquality();
    const list = ListEquality<String>();
    return Object.hash(
      id,
      type,
      title,
      deep.hash(fields),
      list.hash(tags),
      notes,
      favorite,
      revealable,
      createdAt,
      updatedAt,
      deep.hash(extra),
    );
  }

  @override
  String toString() => 'VaultEntry(${type.storageValue}, $title, <redacted>)';
}
