import 'package:flutter/foundation.dart';

import 'claude_credential_link_result.dart';
import 'team_config.dart';

export 'team_config.dart' show CliTool;

/// Provider category for presets and form behavior.
enum AppProviderCategory {
  custom('custom'),
  official('official'),
  cnOfficial('cn_official'),
  cloudProvider('cloud_provider'),
  thirdParty('third_party'),
  aggregator('aggregator');

  const AppProviderCategory(this.value);

  final String value;

  static AppProviderCategory fromJson(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    for (final c in AppProviderCategory.values) {
      if (c.value == s) return c;
    }
    return AppProviderCategory.custom;
  }
}

@immutable
class AppProviderConfig {
  const AppProviderConfig({
    required this.id,
    required this.cli,
    required this.name,
    this.notes = '',
    this.websiteUrl = '',
    this.apiKeyUrl = '',
    this.category = AppProviderCategory.custom,
    this.apiKey = '',
    this.apiKeyField = 'api_key',
    this.baseUrl = '',
    this.defaultModel = '',
    this.icon = '',
    this.iconColor = '',
    this.isOfficial = false,
    this.isPartner = false,
    this.partnerPromotionKey = '',
    this.endpointCandidates = const [],
    this.config = const {},
    this.createdAt = 0,
    this.updatedAt = 0,
    this.credentialStatus = 'missing',
    this.credentialUpdatedAt = 0,
    this.unknownFields = const {},
  });

  factory AppProviderConfig.fromJson(
    Map<String, Object?> json, {
    CliTool? cliFallback,
  }) {
    final id = json['id'] as String? ?? '';
    final endpointRaw = json['endpointCandidates'];
    final endpoints = endpointRaw is List
        ? endpointRaw
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final configRaw = json['config'];
    return AppProviderConfig(
      id: id,
      cli: CliTool.parse(json['cli'], fallback: cliFallback),
      name: json['name'] as String? ?? id,
      notes: json['notes'] as String? ?? '',
      websiteUrl: json['websiteUrl'] as String? ?? '',
      apiKeyUrl: json['apiKeyUrl'] as String? ?? '',
      category: AppProviderCategory.fromJson(json['category']),
      apiKey: json['apiKey'] as String? ?? '',
      apiKeyField: json['apiKeyField'] as String? ?? 'api_key',
      baseUrl: json['baseUrl'] as String? ?? '',
      defaultModel: json['defaultModel'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      iconColor: json['iconColor'] as String? ?? '',
      isOfficial: json['isOfficial'] as bool? ?? false,
      isPartner: json['isPartner'] as bool? ?? false,
      partnerPromotionKey: json['partnerPromotionKey'] as String? ?? '',
      endpointCandidates: endpoints,
      config: configRaw is Map
          ? Map<String, Object?>.from(configRaw)
          : const {},
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      credentialStatus: json['credentialStatus'] as String? ?? 'missing',
      credentialUpdatedAt: (json['credentialUpdatedAt'] as num?)?.toInt() ?? 0,
      unknownFields: {
        for (final entry in json.entries)
          if (!_knownKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  static const _knownKeys = {
    'id',
    'cli',
    'name',
    'notes',
    'websiteUrl',
    'apiKeyUrl',
    'category',
    'apiKey',
    'apiKeyField',
    'baseUrl',
    'defaultModel',
    'icon',
    'iconColor',
    'isOfficial',
    'isPartner',
    'partnerPromotionKey',
    'endpointCandidates',
    'config',
    'createdAt',
    'updatedAt',
    'credentialStatus',
    'credentialUpdatedAt',
  };

  final String id;
  final CliTool cli;
  final String name;
  final String notes;
  final String websiteUrl;
  final String apiKeyUrl;
  final AppProviderCategory category;
  final String apiKey;
  final String apiKeyField;
  final String baseUrl;
  final String defaultModel;
  final String icon;
  final String iconColor;
  final bool isOfficial;
  final bool isPartner;
  final String partnerPromotionKey;
  final List<String> endpointCandidates;
  final Map<String, Object?> config;
  final int createdAt;
  final int updatedAt;
  final String credentialStatus;
  final int credentialUpdatedAt;
  final Map<String, Object?> unknownFields;

  bool get hasClaudeCredentialsReady => credentialStatus == 'ready';

  bool get requiresApiKey =>
      category == AppProviderCategory.thirdParty ||
      category == AppProviderCategory.aggregator ||
      category == AppProviderCategory.cnOfficial;

  int get flashskyaiModelCount {
    if (cli != CliTool.flashskyai) return 0;
    final raw = config['models'];
    if (raw is Map) return raw.length;
    if (defaultModel.trim().isNotEmpty) return 1;
    return 0;
  }

  AppProviderConfig copyWith({
    String? id,
    CliTool? cli,
    String? name,
    String? notes,
    String? websiteUrl,
    String? apiKeyUrl,
    AppProviderCategory? category,
    String? apiKey,
    String? apiKeyField,
    String? baseUrl,
    String? defaultModel,
    String? icon,
    String? iconColor,
    bool? isOfficial,
    bool? isPartner,
    String? partnerPromotionKey,
    List<String>? endpointCandidates,
    Map<String, Object?>? config,
    int? createdAt,
    int? updatedAt,
    String? credentialStatus,
    int? credentialUpdatedAt,
    Map<String, Object?>? unknownFields,
  }) {
    return AppProviderConfig(
      id: id ?? this.id,
      cli: cli ?? this.cli,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      apiKeyUrl: apiKeyUrl ?? this.apiKeyUrl,
      category: category ?? this.category,
      apiKey: apiKey ?? this.apiKey,
      apiKeyField: apiKeyField ?? this.apiKeyField,
      baseUrl: baseUrl ?? this.baseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      icon: icon ?? this.icon,
      iconColor: iconColor ?? this.iconColor,
      isOfficial: isOfficial ?? this.isOfficial,
      isPartner: isPartner ?? this.isPartner,
      partnerPromotionKey: partnerPromotionKey ?? this.partnerPromotionKey,
      endpointCandidates: endpointCandidates ?? this.endpointCandidates,
      config: config ?? this.config,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      credentialStatus: credentialStatus ?? this.credentialStatus,
      credentialUpdatedAt: credentialUpdatedAt ?? this.credentialUpdatedAt,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  AppProviderConfig withCredentialProbe(CredentialProbe probe) => copyWith(
    credentialStatus: probe.isReady ? 'ready' : 'missing',
    credentialUpdatedAt:
        probe.updatedAt?.millisecondsSinceEpoch ?? credentialUpdatedAt,
  );

  Map<String, Object?> toJson() {
    return {
      ...unknownFields,
      'id': id,
      'cli': cli.value,
      'name': name,
      'notes': notes,
      'websiteUrl': websiteUrl,
      'apiKeyUrl': apiKeyUrl,
      'category': category.value,
      'apiKey': apiKey,
      'apiKeyField': apiKeyField,
      'baseUrl': baseUrl,
      'defaultModel': defaultModel,
      if (icon.isNotEmpty) 'icon': icon,
      if (iconColor.isNotEmpty) 'iconColor': iconColor,
      'isOfficial': isOfficial,
      'isPartner': isPartner,
      'partnerPromotionKey': partnerPromotionKey,
      'endpointCandidates': endpointCandidates,
      'config': config,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (cli == CliTool.claude) ...{
        'credentialStatus': credentialStatus,
        if (credentialUpdatedAt > 0) 'credentialUpdatedAt': credentialUpdatedAt,
      },
    };
  }
}

@immutable
class AppProviderPreset {
  const AppProviderPreset({
    required this.id,
    required this.label,
    required this.template,
  });

  final String id;
  final String label;
  final AppProviderConfig template;
}
