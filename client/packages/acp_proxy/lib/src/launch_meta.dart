/// Permission policy from `session/new` `_meta.teampilot`.
enum AcpProxyPermissionPolicy { fullAccess, ask }

/// CLI launch fields carried in `session/new` `_meta.teampilot`.
class AcpProxyLaunchMeta {
  const AcpProxyLaunchMeta({
    required this.cli,
    required this.executable,
    required this.args,
    required this.env,
    required this.permissionPolicy,
    this.authenticateMethodId,
  });

  final String cli;
  final String executable;
  final List<String> args;
  final Map<String, String> env;
  final AcpProxyPermissionPolicy permissionPolicy;

  /// Optional ACP `authenticate` method. Absent or empty skips authenticate.
  final String? authenticateMethodId;

  /// Reads only the `teampilot` map. [args] defaults to empty.
  ///
  /// Throws [FormatException] when `teampilot` is missing, [cli] differs from
  /// [endpointCli], [executable] is empty, [permissionPolicy] is not
  /// `fullAccess` or `ask`, or an [env] value is not a string.
  factory AcpProxyLaunchMeta.parse({
    required String endpointCli,
    required Map<String, Object?> meta,
  }) {
    final raw = meta['teampilot'];
    if (raw is! Map) {
      throw const FormatException('session/new _meta.teampilot is missing');
    }
    final teampilot = Map<Object?, Object?>.from(raw);
    final cli = teampilot['cli'];
    if (cli is! String || cli != endpointCli) {
      throw FormatException(
        'session/new _meta.teampilot.cli must be $endpointCli',
      );
    }
    final executable = teampilot['executable'];
    if (executable is! String || executable.isEmpty) {
      throw const FormatException(
        'session/new _meta.teampilot.executable must be a non-empty string',
      );
    }
    return AcpProxyLaunchMeta(
      cli: cli,
      executable: executable,
      args: _stringList(teampilot['args']),
      env: _stringMap(teampilot['env']),
      permissionPolicy: _permissionPolicy(teampilot['permissionPolicy']),
      authenticateMethodId: _optionalMethod(teampilot['authenticateMethodId']),
    );
  }
}

List<String> _stringList(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException(
      'session/new _meta.teampilot.args must be a list of strings',
    );
  }
  final args = <String>[];
  for (final item in raw) {
    if (item is! String) {
      throw const FormatException(
        'session/new _meta.teampilot.args must be a list of strings',
      );
    }
    args.add(item);
  }
  return List<String>.unmodifiable(args);
}

Map<String, String> _stringMap(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw const FormatException(
      'session/new _meta.teampilot.env values must be strings',
    );
  }
  final env = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! String) {
      throw const FormatException(
        'session/new _meta.teampilot.env values must be strings',
      );
    }
    env[key] = value;
  }
  return Map<String, String>.unmodifiable(env);
}

String? _optionalMethod(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException(
      'session/new _meta.teampilot.authenticateMethodId must be a string',
    );
  }
  if (raw.isEmpty) return null;
  return raw;
}

AcpProxyPermissionPolicy _permissionPolicy(Object? raw) {
  return switch (raw) {
    'fullAccess' => AcpProxyPermissionPolicy.fullAccess,
    'ask' => AcpProxyPermissionPolicy.ask,
    _ => throw const FormatException(
      'session/new _meta.teampilot.permissionPolicy must be fullAccess or ask',
    ),
  };
}
