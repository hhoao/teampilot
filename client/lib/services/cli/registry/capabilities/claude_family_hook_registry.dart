import 'cli_asset_registry.dart';
import 'cli_config_asset.dart';
import 'hook_registry.dart';

/// claude / flashskyai 共享：settings.json `hooks` 段的渲染实现。
/// 语法收敛自 agent_status_hooks.dart + bus_idle_stop_hook.dart。
/// 有可变状态（继承 CliAssetRegistry 的注册表），不可 const。
final class ClaudeFamilyHookRegistry extends CliAssetRegistry<CliHookSpec>
    implements HookRegistry {
  ClaudeFamilyHookRegistry();

  @override
  Map<String, String> get eventNameMap => const {
    'promptSubmit': 'UserPromptSubmit',
    'stop': 'Stop',
  };

  /// 幂等合并：按 (event, url|command) 查重，重复不追加。
  @override
  Map<String, Object?> render(List<CliConfigAsset<CliHookSpec>> assets) {
    final hooks = <String, Object?>{};
    for (final asset in assets) {
      final spec = asset.payload;
      final nativeEvent = eventNameMap[spec.event] ?? spec.event;
      final entries =
          List<Object?>.from((hooks[nativeEvent] as List?) ?? const []);
      final entry = <String, Object?>{
        'hooks': [
          if (spec.url != null)
            {
              'type': 'http',
              'url': spec.url,
              'headers': spec.headers,
              if (spec.timeout != null)
                'timeout': spec.timeout!.inSeconds,
            }
          else if (spec.command != null)
            {'type': 'command', 'command': spec.command, 'timeout': 5},
        ],
      };
      final dupKey = spec.url ?? spec.command;
      final exists = entries.any(
        (e) =>
            e is Map &&
            (e['hooks'] as List?)?.any(
                  (h) =>
                      h is Map &&
                      ((h['url'] ?? h['command']) == dupKey),
                ) ==
                true,
      );
      if (!exists) entries.add(entry);
      hooks[nativeEvent] = entries;
    }
    return {'settings.json': {'hooks': hooks}};
  }

  @override
  List<GeneratedScript> generateScripts(
    List<CliConfigAsset<CliHookSpec>> assets,
  ) {
    // blockOnDecision 的 idle 类钩子：包装 command 并在末尾 exit 2（block，
    // decision:block 语义）。文件名取自 command 引用的脚本（bash <ref>）。
    final scripts = <GeneratedScript>[];
    for (final asset in assets) {
      final spec = asset.payload;
      if (!spec.blockOnDecision || spec.command == null) continue;
      final ref = spec.command!.split(RegExp(r'\s+')).last;
      scripts.add(GeneratedScript(
        fileName: ref.isEmpty ? 'hook.sh' : ref,
        content: [
          '#!/usr/bin/env bash',
          '# TeamPilot ${spec.event} idle hook: exit 2 = block (decision:block).',
          spec.command!,
          'exit 2',
        ].join('\n'),
      ));
    }
    return scripts;
  }
}

/// 装配点工具：把 [hooksSection]（render 输出的 `settings.json` 片段）幂等并入
/// settings 的 `hooks` 段（按 (event, url|command) 判重，重复不追加）。
Map<String, Object?> mergeHooksInto(
  Map<String, Object?> settings,
  Map<String, Object?> hooksSection,
) {
  final merged = Map<String, Object?>.from(settings);
  final hooks = Map<String, Object?>.from(
    (merged['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  for (final entry in (hooksSection['hooks'] as Map).entries) {
    final event = entry.key as String;
    final incoming = List<Object?>.from((entry.value as List?) ?? const []);
    final existing = List<Object?>.from((hooks[event] as List?) ?? const []);
    for (final inc in incoming) {
      if (!existing.any((e) => _sameHookEntry(e, inc))) existing.add(inc);
    }
    hooks[event] = existing;
  }
  merged['hooks'] = hooks;
  return merged;
}

bool _sameHookEntry(Object? a, Object? b) {
  if (a is! Map || b is! Map) return false;
  final ha = a['hooks'];
  final hb = b['hooks'];
  if (ha is! List || hb is! List || ha.isEmpty || hb.isEmpty) return false;
  final fa = ha.first as Map;
  final fb = hb.first as Map;
  return (fa['url'] ?? fa['command']) == (fb['url'] ?? fb['command']);
}
