import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Resolves `${extensionPath}` for an extension id when building adapter commands.
typedef ExtensionPathResolver = String Function(String extensionId);

/// Timeouts for Launch Adapter JSON-RPC requests.
abstract final class LaunchAdapterTimeouts {
  static const Duration initialize = Duration(seconds: 15);
  static const Duration launch = Duration(seconds: 30);
  static const Duration request = Duration(seconds: 15);
}

/// Supported [LaunchOption.type] values in v1.
enum LaunchOptionType {
  string,
  boolean,
  choice,
  file,
  folder;

  static LaunchOptionType parse(String? raw) {
    return switch (raw) {
      'boolean' => LaunchOptionType.boolean,
      'choice' => LaunchOptionType.choice,
      'file' => LaunchOptionType.file,
      'folder' => LaunchOptionType.folder,
      _ => LaunchOptionType.string,
    };
  }

  String get wireName => name;
}

/// One choice entry for a [LaunchOptionType.choice] option.
@immutable
class LaunchOptionChoice {
  const LaunchOptionChoice({required this.value, required this.label});

  final String value;
  final String label;

  factory LaunchOptionChoice.fromJson(Map<String, Object?> json) {
    return LaunchOptionChoice(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? json['value']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {'value': value, 'label': label};
}

/// Dynamic option contributed by a Launch Adapter.
@immutable
class LaunchOption {
  const LaunchOption({
    required this.id,
    required this.label,
    required this.type,
    this.value,
    this.choices = const [],
  });

  final String id;
  final String label;
  final LaunchOptionType type;
  final Object? value;
  final List<LaunchOptionChoice> choices;

  factory LaunchOption.fromJson(Map<String, Object?> json) {
    final rawChoices = json['choices'];
    return LaunchOption(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: LaunchOptionType.parse(json['type'] as String?),
      value: json['value'],
      choices: rawChoices is List
          ? rawChoices
                .whereType<Map>()
                .map(
                  (e) => LaunchOptionChoice.fromJson(
                    Map<String, Object?>.from(e),
                  ),
                )
                .toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'type': type.wireName,
    if (value != null) 'value': value,
    if (choices.isNotEmpty) 'choices': choices.map((c) => c.toJson()).toList(),
  };
}

/// Dynamic configuration / action entry from `configurationsChanged`.
@immutable
class LaunchAdapterConfigurationEntry {
  const LaunchAdapterConfigurationEntry({
    required this.id,
    required this.name,
    required this.type,
    this.isAction = false,
    this.extras = const {},
  });

  final String id;
  final String name;
  final String type;
  final bool isAction;
  final Map<String, Object?> extras;

  factory LaunchAdapterConfigurationEntry.fromJson(Map<String, Object?> json) {
    const known = {'id', 'name', 'type', 'isAction'};
    final extras = <String, Object?>{};
    for (final entry in json.entries) {
      if (!known.contains(entry.key)) {
        extras[entry.key] = entry.value;
      }
    }
    return LaunchAdapterConfigurationEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      isAction: json['isAction'] == true,
      extras: extras,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    if (isAction) 'isAction': true,
    ...extras,
  };
}

/// Adapter → platform `output` notification.
@immutable
class LaunchAdapterOutputEvent {
  const LaunchAdapterOutputEvent({
    required this.sessionId,
    required this.category,
    required this.data,
  });

  final String sessionId;
  final String category;
  final String data;

  factory LaunchAdapterOutputEvent.fromParams(Map<String, Object?> params) {
    return LaunchAdapterOutputEvent(
      sessionId: params['sessionId']?.toString() ?? '',
      category: params['category']?.toString() ?? 'stdout',
      data: params['data']?.toString() ?? '',
    );
  }
}

/// Adapter → platform `exited` notification.
@immutable
class LaunchAdapterExitedEvent {
  const LaunchAdapterExitedEvent({
    required this.sessionId,
    required this.exitCode,
  });

  final String sessionId;
  final int exitCode;

  factory LaunchAdapterExitedEvent.fromParams(Map<String, Object?> params) {
    final raw = params['exitCode'];
    final code = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 1;
    return LaunchAdapterExitedEvent(
      sessionId: params['sessionId']?.toString() ?? '',
      exitCode: code,
    );
  }
}

/// Result of `configureAction`.
@immutable
class ConfigureActionResult {
  const ConfigureActionResult({
    this.configuration,
    this.persist = false,
    this.cancelled = false,
  });

  final Map<String, Object?>? configuration;
  final bool persist;
  final bool cancelled;

  factory ConfigureActionResult.fromJson(Map<String, Object?> json) {
    if (json['cancelled'] == true) {
      return const ConfigureActionResult(cancelled: true);
    }
    final raw = json['configuration'];
    return ConfigureActionResult(
      configuration: raw is Map
          ? Map<String, Object?>.from(raw)
          : null,
      persist: json['persist'] == true,
    );
  }
}

/// JSON-RPC 2.0 message helpers for newline-delimited Launch Adapter framing.
abstract final class LaunchAdapterProtocol {
  static const String jsonrpc = '2.0';

  static const String methodInitialize = 'initialize';
  static const String methodLaunch = 'launch';
  static const String methodStop = 'stop';
  static const String methodShutdown = 'shutdown';
  static const String methodProvideOptions = 'provideOptions';
  static const String methodConfigureAction = 'configureAction';

  static const String notifyOutput = 'output';
  static const String notifyExited = 'exited';
  static const String notifyOptionsChanged = 'optionsChanged';
  static const String notifyConfigurationsChanged = 'configurationsChanged';
  static const String notifyError = 'error';

  static String encodeRequest({
    required Object id,
    required String method,
    Map<String, Object?>? params,
  }) {
    return jsonEncode({
      'jsonrpc': jsonrpc,
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
  }

  static String encodeNotification({
    required String method,
    Map<String, Object?>? params,
  }) {
    return jsonEncode({
      'jsonrpc': jsonrpc,
      'id': null,
      'method': method,
      if (params != null) 'params': params,
    });
  }

  /// Parses one newline-delimited JSON-RPC object.
  ///
  /// Returns null when [line] is empty, not JSON, or not a JSON object.
  static Map<String, Object?>? decodeLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    }
  }

  static bool isResponse(Map<String, Object?> message) {
    return message.containsKey('result') || message.containsKey('error');
  }

  static bool isNotification(Map<String, Object?> message) {
    return message['method'] is String && !isResponse(message);
  }

  static Map<String, Object?> paramsOf(Map<String, Object?> message) {
    final raw = message['params'];
    if (raw is Map) return Map<String, Object?>.from(raw);
    return const {};
  }

  static List<LaunchOption> parseOptions(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LaunchOption.fromJson(Map<String, Object?>.from(e)))
        .toList();
  }

  static List<LaunchAdapterConfigurationEntry> parseConfigurationEntries(
    Object? raw,
  ) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (e) => LaunchAdapterConfigurationEntry.fromJson(
            Map<String, Object?>.from(e),
          ),
        )
        .toList();
  }

  /// Expands `${extensionPath}` using [resolver] when [extensionId] is set.
  static String expandAdapterCommand({
    required String command,
    required String? extensionId,
    required ExtensionPathResolver resolver,
  }) {
    if (!command.contains(r'${extensionPath}')) return command;
    final path = extensionId == null || extensionId.isEmpty
        ? ''
        : resolver(extensionId);
    return command.replaceAll(r'${extensionPath}', path);
  }

  /// Splits an adapter command string into executable + args (whitespace).
  static (String executable, List<String> arguments) splitCommand(
    String command,
  ) {
    final parts = command
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return ('', const []);
    }
    return (parts.first, parts.sublist(1));
  }
}
