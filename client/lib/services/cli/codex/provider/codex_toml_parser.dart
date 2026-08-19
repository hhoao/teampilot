import 'package:toml/toml.dart';

/// Parses Codex `config.toml` snippets and detects CC Switch proxy takeover.
class CodexTomlParser {
  const CodexTomlParser._();

  static const proxyManagedToken = 'PROXY_MANAGED';

  /// Codex hook `type` whitelist — the CLI's hook serde only accepts these.
  ///
  /// Anything else (e.g. `http`) makes codex refuse to load the whole
  /// `config.toml` at startup ("unknown variant ... in `hooks`").
  static const Set<String> allowedHookTypes = {'command', 'prompt', 'agent'};

  /// Collects every `type = "…"` under `[[hooks.*]]` tables (including
  /// `[[hooks.*.hooks]]` rows) that is not in [allowedHookTypes], in document
  /// order. Empty result = valid.
  ///
  /// Throws a [TomlException] when the document does not parse — callers
  /// should run a syntax check first (see
  /// [ToolConfigGenerator.validateCodexToml]).
  static List<String> invalidHookTypes(String toml) {
    final map = TomlDocument.parse(toml).toMap();
    final hooks = map['hooks'];
    if (hooks is! Map) return const [];
    final invalid = <String>[];
    for (final event in hooks.values) {
      if (event is! List) continue;
      for (final row in event) {
        if (row is Map) _collectInvalid(row, invalid);
      }
    }
    return invalid;
  }

  /// Drops hook handlers whose `type` is not in [allowedHookTypes].
  ///
  /// Used when rewriting `config.toml` so leftover native `http` rows from
  /// older TeamPilot writers cannot make Codex refuse to load the file.
  static void removeInvalidHooks(Map<String, dynamic> root) {
    final hooks = root['hooks'];
    if (hooks is! Map) return;
    final cleaned = <String, dynamic>{};
    for (final entry in hooks.entries) {
      final key = entry.key.toString();
      final event = entry.value;
      if (event is! List) {
        cleaned[key] = event;
        continue;
      }
      final kept = <dynamic>[];
      for (final row in event) {
        if (row is! Map) {
          kept.add(row);
          continue;
        }
        final cleanedRow = _cleanedHookRow(Map<dynamic, dynamic>.from(row));
        if (cleanedRow != null) kept.add(cleanedRow);
      }
      if (kept.isNotEmpty) cleaned[key] = kept;
    }
    if (cleaned.isEmpty) {
      root.remove('hooks');
    } else {
      root['hooks'] = cleaned;
    }
  }

  static Map<dynamic, dynamic>? _cleanedHookRow(Map<dynamic, dynamic> row) {
    final type = row['type'];
    if (type != null && !allowedHookTypes.contains(type.toString())) {
      return null;
    }
    final nested = row['hooks'];
    if (nested is! List) return row;
    final kept = <dynamic>[];
    for (final inner in nested) {
      if (inner is! Map) {
        kept.add(inner);
        continue;
      }
      final cleanedInner = _cleanedHookRow(Map<dynamic, dynamic>.from(inner));
      if (cleanedInner != null) kept.add(cleanedInner);
    }
    if (kept.isEmpty && type == null) return null;
    return Map<dynamic, dynamic>.from(row)..['hooks'] = kept;
  }

  static void _collectInvalid(Map<dynamic, dynamic> row, List<String> out) {
    final type = row['type'];
    if (type != null) {
      final text = type.toString();
      if (!allowedHookTypes.contains(text)) out.add(text);
    }
    final nested = row['hooks'];
    if (nested is List) {
      for (final inner in nested) {
        if (inner is Map) _collectInvalid(inner, out);
      }
    }
  }

  static CodexTomlParts parse(String toml) {
    final model =
        RegExp(
          r'^\s*model\s*=\s*"([^"]+)"',
          multiLine: true,
        ).firstMatch(toml)?.group(1) ??
        '';
    final baseUrl =
        RegExp(
          r'^\s*base_url\s*=\s*"([^"]+)"',
          multiLine: true,
        ).firstMatch(toml)?.group(1) ??
        '';
    return CodexTomlParts(model: model, baseUrl: baseUrl);
  }

  static bool detectProxyTakeover({
    required String liveToml,
    required Map<String, Object?> liveAuth,
  }) {
    final apiKey = liveAuth['OPENAI_API_KEY']?.toString() ?? '';
    if (apiKey == proxyManagedToken) return true;
    if (liveToml.contains('experimental_bearer_token = "$proxyManagedToken"')) {
      return true;
    }
    final baseUrl = parse(liveToml).baseUrl.toLowerCase();
    if (baseUrl.isEmpty) return false;
    return baseUrl.contains('127.0.0.1') ||
        baseUrl.contains('localhost') ||
        baseUrl.contains(':15721');
  }
}

class CodexTomlParts {
  const CodexTomlParts({required this.model, required this.baseUrl});

  final String model;
  final String baseUrl;
}
