import 'package:flutter/foundation.dart';

@immutable
class RemoteDownloadSource {
  const RemoteDownloadSource({
    required this.id,
    required this.priority,
    required this.enabled,
    required this.matchHosts,
    this.matchPathPrefix,
    this.rewriteOrigin,
  });

  factory RemoteDownloadSource.fromJson(Map<String, Object?> json) {
    return RemoteDownloadSource(
      id: json['id'] as String? ?? '',
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      matchHosts: (json['matchHosts'] as List<Object?>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      matchPathPrefix: json['matchPathPrefix'] as String?,
      rewriteOrigin: json['rewriteOrigin'] as String?,
    );
  }

  final String id;
  final int priority;
  final bool enabled;
  final List<String> matchHosts;
  final String? matchPathPrefix;
  final String? rewriteOrigin;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'priority': priority,
      'enabled': enabled,
      'matchHosts': matchHosts,
      if (matchPathPrefix != null) 'matchPathPrefix': matchPathPrefix,
      if (rewriteOrigin != null) 'rewriteOrigin': rewriteOrigin,
    };
  }

  RemoteDownloadSource copyWith({
    String? id,
    int? priority,
    bool? enabled,
    List<String>? matchHosts,
    String? matchPathPrefix,
    String? rewriteOrigin,
  }) {
    return RemoteDownloadSource(
      id: id ?? this.id,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
      matchHosts: matchHosts ?? this.matchHosts,
      matchPathPrefix: matchPathPrefix ?? this.matchPathPrefix,
      rewriteOrigin: rewriteOrigin ?? this.rewriteOrigin,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RemoteDownloadSource &&
            id == other.id &&
            priority == other.priority &&
            enabled == other.enabled &&
            listEquals(matchHosts, other.matchHosts) &&
            matchPathPrefix == other.matchPathPrefix &&
            rewriteOrigin == other.rewriteOrigin;
  }

  @override
  int get hashCode => Object.hash(
        id,
        priority,
        enabled,
        Object.hashAll(matchHosts),
        matchPathPrefix,
        rewriteOrigin,
      );
}
