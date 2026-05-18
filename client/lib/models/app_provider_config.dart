import 'package:flutter/foundation.dart';

/// Tool identifiers supported by unified app-level providers.
enum AppProviderTool {
  flashskyai('flashskyai'),
  codex('codex'),
  claude('claude');

  const AppProviderTool(this.value);

  final String value;

  static AppProviderTool? tryParse(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final tool in AppProviderTool.values) {
      if (tool.value == normalized) return tool;
    }
    return null;
  }
}

/// Provider category for presets and form behavior.
enum AppProviderCategory {
  custom('custom'),
  official('official'),
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
class AppProviderToolConfigPayload {
  const AppProviderToolConfigPayload({this.unknownFields = const {}});

  factory AppProviderToolConfigPayload.fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) {
      return const AppProviderToolConfigPayload();
    }
    return AppProviderToolConfigPayload(
      unknownFields: Map<String, Object?>.from(json),
    );
  }

  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => Map<String, Object?>.from(unknownFields);

  AppProviderToolConfigPayload copyWith({Map<String, Object?>? unknownFields}) {
    return AppProviderToolConfigPayload(
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }
}

@immutable
class AppProviderToolConfigs {
  const AppProviderToolConfigs({
    this.flashskyai = const AppProviderToolConfigPayload(),
    this.codex = const AppProviderToolConfigPayload(),
    this.claude = const AppProviderToolConfigPayload(),
  });

  factory AppProviderToolConfigs.fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) {
      return const AppProviderToolConfigs();
    }
    return AppProviderToolConfigs(
      flashskyai: AppProviderToolConfigPayload.fromJson(
        _toolMap(json, AppProviderTool.flashskyai.value),
      ),
      codex: AppProviderToolConfigPayload.fromJson(
        _toolMap(json, AppProviderTool.codex.value),
      ),
      claude: AppProviderToolConfigPayload.fromJson(
        _toolMap(json, AppProviderTool.claude.value),
      ),
    );
  }

  static Map<String, Object?>? _toolMap(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    return null;
  }

  final AppProviderToolConfigPayload flashskyai;
  final AppProviderToolConfigPayload codex;
  final AppProviderToolConfigPayload claude;

  AppProviderToolConfigPayload forTool(AppProviderTool tool) {
    return switch (tool) {
      AppProviderTool.flashskyai => flashskyai,
      AppProviderTool.codex => codex,
      AppProviderTool.claude => claude,
    };
  }

  Map<String, Object?> toJson() {
    return {
      AppProviderTool.flashskyai.value: flashskyai.toJson(),
      AppProviderTool.codex.value: codex.toJson(),
      AppProviderTool.claude.value: claude.toJson(),
    };
  }

  AppProviderToolConfigs copyWith({
    AppProviderToolConfigPayload? flashskyai,
    AppProviderToolConfigPayload? codex,
    AppProviderToolConfigPayload? claude,
  }) {
    return AppProviderToolConfigs(
      flashskyai: flashskyai ?? this.flashskyai,
      codex: codex ?? this.codex,
      claude: claude ?? this.claude,
    );
  }
}

@immutable
class AppProviderConfig {
  const AppProviderConfig({
    required this.id,
    required this.name,
    this.notes = '',
    this.websiteUrl = '',
    this.category = AppProviderCategory.custom,
    this.apiKey = '',
    this.apiKeyField = 'api_key',
    this.baseUrl = '',
    this.defaultModel = '',
    this.icon = '',
    this.enabledTools = const [],
    this.toolConfigs = const AppProviderToolConfigs(),
    this.commonConfigEnabled = false,
    this.managedAccountId = '', // Legacy import metadata only.
    this.createdAt = 0,
    this.updatedAt = 0,
    this.unknownFields = const {},
  });

  factory AppProviderConfig.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? '';
    final enabledRaw = json['enabledTools'];
    final enabled = <AppProviderTool>[];
    if (enabledRaw is List) {
      for (final entry in enabledRaw) {
        final tool = AppProviderTool.tryParse(entry?.toString() ?? '');
        if (tool != null) enabled.add(tool);
      }
    }

    final toolConfigsRaw = json['toolConfigs'];
    return AppProviderConfig(
      id: id,
      name: json['name'] as String? ?? id,
      notes: json['notes'] as String? ?? '',
      websiteUrl: json['websiteUrl'] as String? ?? '',
      category: AppProviderCategory.fromJson(json['category']),
      apiKey: json['apiKey'] as String? ?? '',
      apiKeyField: json['apiKeyField'] as String? ?? 'api_key',
      baseUrl: json['baseUrl'] as String? ?? '',
      defaultModel: json['defaultModel'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      enabledTools: enabled,
      toolConfigs: toolConfigsRaw is Map
          ? AppProviderToolConfigs.fromJson(
              Map<String, Object?>.from(toolConfigsRaw),
            )
          : const AppProviderToolConfigs(),
      commonConfigEnabled: json['commonConfigEnabled'] as bool? ?? false,
      managedAccountId: json['managedAccountId'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      unknownFields: {
        for (final entry in json.entries)
          if (!_knownKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  static const _knownKeys = {
    'id',
    'name',
    'notes',
    'websiteUrl',
    'category',
    'apiKey',
    'apiKeyField',
    'baseUrl',
    'defaultModel',
    'icon',
    'enabledTools',
    'toolConfigs',
    'commonConfigEnabled',
    'managedAccountId',
    'createdAt',
    'updatedAt',
  };

  final String id;
  final String name;
  final String notes;
  final String websiteUrl;
  final AppProviderCategory category;
  final String apiKey;
  final String apiKeyField;
  final String baseUrl;
  final String defaultModel;
  final String icon;
  final List<AppProviderTool> enabledTools;
  final AppProviderToolConfigs toolConfigs;
  final bool commonConfigEnabled;

  /// Legacy import metadata. Do not resolve into legacy account profile dirs.
  final String managedAccountId;
  final int createdAt;
  final int updatedAt;
  final Map<String, Object?> unknownFields;

  bool enables(AppProviderTool tool) => enabledTools.contains(tool);

  bool get requiresApiKey =>
      category == AppProviderCategory.thirdParty ||
      category == AppProviderCategory.aggregator;

  AppProviderConfig copyWith({
    String? id,
    String? name,
    String? notes,
    String? websiteUrl,
    AppProviderCategory? category,
    String? apiKey,
    String? apiKeyField,
    String? baseUrl,
    String? defaultModel,
    String? icon,
    List<AppProviderTool>? enabledTools,
    AppProviderToolConfigs? toolConfigs,
    bool? commonConfigEnabled,
    String? managedAccountId,
    int? createdAt,
    int? updatedAt,
    Map<String, Object?>? unknownFields,
  }) {
    return AppProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      category: category ?? this.category,
      apiKey: apiKey ?? this.apiKey,
      apiKeyField: apiKeyField ?? this.apiKeyField,
      baseUrl: baseUrl ?? this.baseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      icon: icon ?? this.icon,
      enabledTools: enabledTools ?? this.enabledTools,
      toolConfigs: toolConfigs ?? this.toolConfigs,
      commonConfigEnabled: commonConfigEnabled ?? this.commonConfigEnabled,
      managedAccountId: managedAccountId ?? this.managedAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...unknownFields,
      'id': id,
      'name': name,
      'notes': notes,
      'websiteUrl': websiteUrl,
      'category': category.value,
      'apiKey': apiKey,
      'apiKeyField': apiKeyField,
      'baseUrl': baseUrl,
      'defaultModel': defaultModel,
      if (icon.isNotEmpty) 'icon': icon,
      'enabledTools': enabledTools.map((t) => t.value).toList(),
      'toolConfigs': toolConfigs.toJson(),
      'commonConfigEnabled': commonConfigEnabled,
      if (managedAccountId.isNotEmpty) 'managedAccountId': managedAccountId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
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

/// Built-in presets for the add-provider panel.
class AppProviderPresets {
  AppProviderPresets._();

  static const List<AppProviderPreset> all = [
    AppProviderPreset(
      id: 'custom',
      label: 'Custom',
      template: AppProviderConfig(
        id: '',
        name: '',
        category: AppProviderCategory.custom,
        enabledTools: AppProviderTool.values,
      ),
    ),
    AppProviderPreset(
      id: 'deepseek',
      label: 'DeepSeek',
      template: AppProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        websiteUrl: 'https://platform.deepseek.com',
        category: AppProviderCategory.thirdParty,
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-chat',
        enabledTools: [
          AppProviderTool.flashskyai,
          AppProviderTool.codex,
          AppProviderTool.claude,
        ],
        toolConfigs: AppProviderToolConfigs(
          flashskyai: AppProviderToolConfigPayload(
            unknownFields: {'provider_type': 'openai'},
          ),
          codex: AppProviderToolConfigPayload(
            unknownFields: {'wire_api': 'chat'},
          ),
          claude: AppProviderToolConfigPayload(
            unknownFields: {
              'env': {'ANTHROPIC_BASE_URL': 'https://api.deepseek.com'},
            },
          ),
        ),
      ),
    ),
    AppProviderPreset(
      id: 'openai-official',
      label: 'OpenAI (official)',
      template: AppProviderConfig(
        id: 'openai-official',
        name: 'OpenAI',
        websiteUrl: 'https://platform.openai.com',
        category: AppProviderCategory.official,
        enabledTools: [AppProviderTool.codex],
        toolConfigs: AppProviderToolConfigs(
          codex: AppProviderToolConfigPayload(
            unknownFields: {'auth_mode': 'chatgpt'},
          ),
        ),
      ),
    ),
    AppProviderPreset(
      id: 'claude-official',
      label: 'Claude (official)',
      template: AppProviderConfig(
        id: 'claude-official',
        name: 'Claude',
        websiteUrl: 'https://claude.ai',
        category: AppProviderCategory.official,
        enabledTools: [AppProviderTool.claude],
      ),
    ),
  ];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
