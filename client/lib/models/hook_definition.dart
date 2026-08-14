import 'package:flutter/foundation.dart';
import 'hook_entry.dart';
import 'hook_event.dart';

/// 全局库中一个 hook 的持久化定义（`<root>/hooks/{id}/hook.json`）。
///
/// 托管脚本内容不持久化在这里——脚本是 hook 目录下的独立文件
/// （`hook.sh` / `hook.ps1`），[HookLibraryResolver] 加载后填入
/// [CommandHookAction.scriptContent]。
@immutable
class HookDefinition {
  const HookDefinition({
    required this.id,
    this.name = '',
    this.description = '',
    required this.event,
    this.matcher,
    required this.action,
    this.policy = HookPolicy.none,
    this.timeoutSec,
    this.env = const {},
    this.native,
  });

  factory HookDefinition.fromJson(Map<String, Object?> json) {
    final action = _actionFromJson(json['action']);
    return HookDefinition(
      id: (json['id'] as String? ?? '').trim(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      event: HookEvent.tryParse(json['event'] as String?) ?? HookEvent.stop,
      matcher: (json['matcher'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['matcher'] as String).trim(),
      action: action,
      policy: HookPolicy.values.asNameMap()[json['policy']] ?? HookPolicy.none,
      timeoutSec: (json['timeoutSec'] as num?)?.toInt(),
      env: _decodeEnv(json['env']),
      native: _decodeNative(json['native']),
    );
  }

  final String id;
  final String name;
  final String description;
  final HookEvent event;
  final String? matcher;
  final HookAction action;
  final HookPolicy policy;
  final int? timeoutSec;
  final Map<String, String> env;

  /// 导入时保留的原生 handler 字段（旁路，零丢失）。writer 管线不消费，
  /// 仅持久化；未来 writer 可按需读取。
  final Map<String, Object?>? native;

  HookDefinition copyWith({
    String? name,
    String? description,
    HookEvent? event,
    String? matcher,
    HookAction? action,
    HookPolicy? policy,
    int? timeoutSec,
    Map<String, String>? env,
    Object? native = _unset,
  }) => HookDefinition(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    event: event ?? this.event,
    matcher: matcher ?? this.matcher,
    action: action ?? this.action,
    policy: policy ?? this.policy,
    timeoutSec: timeoutSec ?? this.timeoutSec,
    env: env ?? this.env,
    native: identical(native, _unset)
        ? this.native
        : native as Map<String, Object?>?,
  );

  static const _unset = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    if (name.isNotEmpty) 'name': name,
    if (description.isNotEmpty) 'description': description,
    'event': event.name,
    if (matcher != null) 'matcher': matcher,
    'action': _actionToJson(action),
    if (policy != HookPolicy.none) 'policy': policy.name,
    if (timeoutSec != null) 'timeoutSec': timeoutSec,
    if (env.isNotEmpty) 'env': env,
    if (native != null && native!.isNotEmpty) 'native': native,
  };

  static Map<String, Object?> _actionToJson(HookAction action) =>
      switch (action) {
        CommandHookAction c =>
          c.command != null
              ? {'type': 'raw', 'command': c.command}
              : {'type': 'script', 'fileName': c.fileName},
        HttpHookAction h => {
          'type': 'http',
          'url': h.url,
          if (h.headers.isNotEmpty) 'headers': h.headers,
        },
      };

  static HookAction _actionFromJson(Object? raw) {
    final map = raw is Map
        ? raw.cast<String, Object?>()
        : const <String, Object?>{};
    final type = map['type'] as String? ?? 'raw';
    return switch (type) {
      'script' => CommandHookAction.script(
        fileName: map['fileName'] as String? ?? 'hook.sh',
        scriptContent: map['scriptContent'] as String?,
      ),
      'http' => HttpHookAction(
        url: map['url'] as String? ?? '',
        headers: _decodeEnv(map['headers']),
      ),
      _ => CommandHookAction.raw(map['command'] as String? ?? ''),
    };
  }

  static Map<String, String> _decodeEnv(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is String) out[entry.key.toString()] = value;
    }
    return Map.unmodifiable(out);
  }

  static Map<String, Object?>? _decodeNative(Object? raw) {
    if (raw is! Map || raw.isEmpty) return null;
    return Map<String, Object?>.from(raw.cast<String, Object?>());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HookDefinition &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          event == other.event &&
          matcher == other.matcher &&
          action == other.action &&
          policy == other.policy &&
          timeoutSec == other.timeoutSec &&
          mapEquals(env, other.env) &&
          mapEquals(native ?? const {}, other.native ?? const {});

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    event,
    matcher,
    action,
    policy,
    timeoutSec,
    Object.hashAllUnordered(env.keys),
    Object.hashAllUnordered(env.values),
    Object.hashAllUnordered(native?.keys ?? const []),
    Object.hashAllUnordered(native?.values ?? const []),
  );
}
