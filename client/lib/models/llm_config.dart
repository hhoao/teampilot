import 'dart:convert';

class LlmConfig {
  const LlmConfig({
    this.providers = const {},
    this.models = const {},
    this.unknownFields = const {},
  });

  factory LlmConfig.fromJson(Map<String, Object?> json) {
    final providers = <String, LlmProviderConfig>{};
    final rawProviders = json['providers'];
    if (rawProviders is Map) {
      for (final entry in rawProviders.entries) {
        if (entry.key is String && entry.value is Map) {
          providers[entry.key as String] = LlmProviderConfig.fromJson(
            entry.key as String,
            Map<String, Object?>.from(entry.value as Map),
          );
        }
      }
    }

    final models = <String, LlmModelConfig>{};
    final rawModels = json['models'];
    if (rawModels is Map) {
      for (final entry in rawModels.entries) {
        if (entry.key is String && entry.value is Map) {
          models[entry.key as String] = LlmModelConfig.fromJson(
            entry.key as String,
            Map<String, Object?>.from(entry.value as Map),
          );
        }
      }
    }

    return LlmConfig(
      providers: providers,
      models: models,
      unknownFields: {
        for (final entry in json.entries)
          if (entry.key != 'providers' && entry.key != 'models')
            entry.key: entry.value,
      },
    );
  }

  static const maskedSecret = '••••••••';

  final Map<String, LlmProviderConfig> providers;
  final Map<String, LlmModelConfig> models;
  final Map<String, Object?> unknownFields;

  List<String> get validationMessages {
    final messages = <String>[];
    for (final provider in providers.values) {
      if (provider.type == 'api') {
        if (provider.providerType.trim().isEmpty) {
          messages.add('${provider.name} provider type is empty.');
        }
        if (provider.baseUrl.trim().isEmpty) {
          messages.add('${provider.name} base URL is empty.');
        }
        if (provider.apiKey.trim().isEmpty) {
          messages.add('${provider.name} API key is empty.');
        }
      }
      if (provider.proxy && provider.proxyUrl.trim().isEmpty) {
        messages.add('${provider.name} proxy URL is empty.');
      }
    }
    for (final model in models.values) {
      if (!providers.containsKey(model.provider)) {
        messages.add(
          '${model.name} references missing provider ${model.provider}.',
        );
      }
    }
    return messages;
  }

  LlmConfig copyWith({
    Map<String, LlmProviderConfig>? providers,
    Map<String, LlmModelConfig>? models,
    Map<String, Object?>? unknownFields,
  }) {
    return LlmConfig(
      providers: providers ?? this.providers,
      models: models ?? this.models,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  Map<String, Object?> toJson({LlmConfig? previous}) {
    return {
      ...unknownFields,
      'providers': {
        for (final entry in providers.entries)
          entry.key: entry.value.toJson(
            previous: previous?.providers[entry.key],
          ),
      },
      'models': {
        for (final entry in models.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  Map<String, dynamic> toMaskedJson() {
    return {
      ...unknownFields,
      'providers': {
        for (final entry in providers.entries)
          entry.key: entry.value.toJson(maskSecrets: true),
      },
      'models': {
        for (final entry in models.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  String toMaskedJsonString() {
    return const JsonEncoder.withIndent('  ').convert(toMaskedJson());
  }
}

class LlmProviderConfig {
  const LlmProviderConfig({
    required this.name,
    required this.type,
    this.providerType = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.proxy = false,
    this.proxyUrl = '',
    this.accounts = const [],
    this.unknownFields = const {},
  });

  factory LlmProviderConfig.fromJson(String name, Map<String, Object?> json) {
    final rawAccount = json['account'];
    return LlmProviderConfig(
      name: name,
      type: json['type'] as String? ?? '',
      providerType: json['provider_type'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      proxy: json['proxy'] as bool? ?? false,
      proxyUrl: json['proxy_url'] as String? ?? '',
      accounts: rawAccount is List
          ? rawAccount.whereType<String>().toList(growable: false)
          : const [],
      unknownFields: {
        for (final entry in json.entries)
          if (!{
            'type',
            'provider_type',
            'base_url',
            'api_key',
            'proxy',
            'proxy_url',
            'account',
          }.contains(entry.key))
            entry.key: entry.value,
      },
    );
  }

  final String name;
  final String type;
  final String providerType;
  final String baseUrl;
  final String apiKey;
  final bool proxy;
  final String proxyUrl;
  final List<String> accounts;
  final Map<String, Object?> unknownFields;

  LlmProviderConfig copyWith({
    String? name,
    String? type,
    String? providerType,
    String? baseUrl,
    String? apiKey,
    bool? proxy,
    String? proxyUrl,
    List<String>? accounts,
    Map<String, Object?>? unknownFields,
  }) {
    return LlmProviderConfig(
      name: name ?? this.name,
      type: type ?? this.type,
      providerType: providerType ?? this.providerType,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      proxy: proxy ?? this.proxy,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      accounts: accounts ?? this.accounts,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  Map<String, Object?> toJson({
    bool maskSecrets = false,
    LlmProviderConfig? previous,
  }) {
    final json = <String, Object?>{
      ...unknownFields,
      'type': type,
      'proxy': proxy,
    };
    if (type == 'account') {
      json['account'] = accounts;
    } else {
      json['provider_type'] = providerType;
      json['base_url'] = baseUrl;
      json['api_key'] = _apiKeyForJson(
        maskSecrets: maskSecrets,
        previous: previous,
      );
    }
    if (proxyUrl.isNotEmpty || proxy) {
      json['proxy_url'] = proxyUrl;
    }
    return json;
  }

  String _apiKeyForJson({
    required bool maskSecrets,
    required LlmProviderConfig? previous,
  }) {
    if (maskSecrets && apiKey.isNotEmpty) {
      return LlmConfig.maskedSecret;
    }
    if (apiKey == LlmConfig.maskedSecret) {
      return previous?.apiKey ?? '';
    }
    return apiKey;
  }
}

class LlmModelConfig {
  const LlmModelConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.model,
    required this.enabled,
    this.unknownFields = const {},
  });

  factory LlmModelConfig.fromJson(String id, Map<String, Object?> json) {
    return LlmModelConfig(
      id: id,
      name: json['name'] as String? ?? id,
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      unknownFields: {
        for (final entry in json.entries)
          if (!{'name', 'provider', 'model', 'enabled'}.contains(entry.key))
            entry.key: entry.value,
      },
    );
  }

  final String id;
  final String name;
  final String provider;
  final String model;
  final bool enabled;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() {
    return {
      ...unknownFields,
      'name': name,
      'provider': provider,
      'model': model,
      'enabled': enabled,
    };
  }

  LlmModelConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? model,
    bool? enabled,
    Map<String, Object?>? unknownFields,
  }) {
    return LlmModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }
}
