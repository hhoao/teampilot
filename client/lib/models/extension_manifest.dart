/// Declarative description of an external extension (e.g. rtk, codegraph).
///
/// Phase 1 only consumes [detect] and `settings-hook` [effects]; [acquire]
/// is parsed for forward-compatibility (used from Phase 2 onward).
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    this.version = '',
    this.homepage = '',
    this.acquire,
    required this.detect,
    this.effects = const [],
  });

  final String id;
  final String name;
  final String version;
  final String homepage;
  final ExtensionAcquireSpec? acquire;
  final ExtensionDetectSpec detect;
  final List<ExtensionEffect> effects;

  factory ExtensionManifest.fromJson(Map<String, Object?> json) {
    final detectRaw = json['detect'];
    final acquireRaw = json['acquire'];
    final effectsRaw = json['effects'];
    return ExtensionManifest(
      id: (json['id'] as String?)?.trim() ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      homepage: json['homepage'] as String? ?? '',
      acquire: acquireRaw is Map
          ? ExtensionAcquireSpec.fromJson(acquireRaw.cast<String, Object?>())
          : null,
      detect: detectRaw is Map
          ? ExtensionDetectSpec.fromJson(detectRaw.cast<String, Object?>())
          : const ExtensionDetectSpec(executable: ''),
      effects: effectsRaw is List
          ? effectsRaw
              .whereType<Map>()
              .map((e) => ExtensionEffect.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
    );
  }
}

/// How to verify the underlying tool is present and usable on the host.
class ExtensionDetectSpec {
  const ExtensionDetectSpec({
    required this.executable,
    this.versionArgs = const ['--version'],
    this.minVersion,
    this.requires = const [],
  });

  final String executable;
  final List<String> versionArgs;
  final String? minVersion;

  /// Companion binaries that must also be on PATH (e.g. rtk requires `jq`).
  final List<String> requires;

  factory ExtensionDetectSpec.fromJson(Map<String, Object?> json) {
    final versionArgs = json['versionArgs'];
    final requires = json['requires'];
    final minVersionRaw = json['minVersion'] as String?;
    final trimmedMin = minVersionRaw?.trim();
    return ExtensionDetectSpec(
      executable: (json['executable'] as String?)?.trim() ?? '',
      versionArgs: versionArgs is List
          ? versionArgs.map((e) => e.toString()).toList()
          : const ['--version'],
      minVersion:
          trimmedMin == null || trimmedMin.isEmpty ? null : trimmedMin,
      requires: requires is List
          ? requires.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
    );
  }
}

/// One way the extension wires into an agent CLI's config profile.
///
/// [config] holds the full effect map; kind-specific getters read it.
class ExtensionEffect {
  const ExtensionEffect({
    required this.kind,
    this.appliesTo = const [],
    this.config = const {},
  });

  final String kind;
  final List<String> appliesTo;
  final Map<String, Object?> config;

  // settings-hook accessors (Phase 1).
  String? get hookEvent => config['event'] as String?;
  String? get hookMatcher => config['matcher'] as String?;
  String? get scriptAsset => config['scriptAsset'] as String?;
  String? get marker => config['marker'] as String?;

  // mcp-server accessors.
  String? get mcpName => config['name'] as String?;
  Map<String, Object?>? get mcpServer {
    final raw = config['server'];
    return raw is Map ? raw.cast<String, Object?>() : null;
  }

  factory ExtensionEffect.fromJson(Map<String, Object?> json) {
    final appliesTo = json['appliesTo'];
    return ExtensionEffect(
      kind: (json['kind'] as String?)?.trim() ?? '',
      appliesTo: appliesTo is List
          ? appliesTo.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      config: Map<String, Object?>.from(json),
    );
  }
}

/// How to install the underlying tool. Parsed in Phase 1, consumed from Phase 2.
class ExtensionAcquireSpec {
  const ExtensionAcquireSpec({
    required this.kind,
    this.package,
    this.binary,
    this.allowNpx = false,
    this.alternatives = const [],
  });

  final String kind;
  final String? package;
  final String? binary;
  final bool allowNpx;
  final List<String> alternatives;

  factory ExtensionAcquireSpec.fromJson(Map<String, Object?> json) {
    final alternatives = json['alternatives'];
    return ExtensionAcquireSpec(
      kind: (json['kind'] as String?)?.trim() ?? 'none',
      package: json['package'] as String?,
      binary: json['binary'] as String?,
      allowNpx: json['allowNpx'] as bool? ?? false,
      alternatives: alternatives is List
          ? alternatives.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
    );
  }
}
