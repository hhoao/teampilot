import 'dart:io';

/// Merges [requested] over [parent] and drops empty values.
///
/// [Process.start] cannot unset a parent variable. An empty requested value
/// means unset, because `claude-agent-acp` treats `ANTHROPIC_API_KEY: ''` as
/// API-key mode with no key. Do not log either map.
Map<String, String> mergeAcpProxyProcessEnvironment(
  Map<String, String> requested, {
  Map<String, String>? parent,
}) {
  final merged = <String, String>{
    ...parent ?? Platform.environment,
    ...requested,
  };
  merged.removeWhere((_, value) => value.isEmpty);
  return merged;
}
