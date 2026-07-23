/// How to install a skill dependency. Missing acquire on a dep ≡ [kind] `git-dir`.
class SkillAcquireSpec {
  const SkillAcquireSpec({
    required this.kind,
    this.package,
    this.alternatives = const [],
    this.primaryDirectory,
  });

  final String kind;
  final String? package;
  final List<String> alternatives;
  final String? primaryDirectory;

  factory SkillAcquireSpec.fromJson(Map<String, Object?> json) {
    final alternatives = json['alternatives'];
    final primaryRaw = json['primaryDirectory'] as String?;
    final trimmedPrimary = primaryRaw?.trim();
    return SkillAcquireSpec(
      kind: (json['kind'] as String?)?.trim() ?? 'git-dir',
      package: json['package'] as String?,
      alternatives: alternatives is List
          ? alternatives
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      primaryDirectory: trimmedPrimary == null || trimmedPrimary.isEmpty
          ? null
          : trimmedPrimary,
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (package != null) 'package': package,
    if (alternatives.isNotEmpty) 'alternatives': alternatives,
    if (primaryDirectory != null && primaryDirectory!.isNotEmpty)
      'primaryDirectory': primaryDirectory,
  };

  SkillAcquireSpec copyWith({
    String? kind,
    String? package,
    List<String>? alternatives,
    String? primaryDirectory,
    bool clearPrimaryDirectory = false,
  }) => SkillAcquireSpec(
    kind: kind ?? this.kind,
    package: package ?? this.package,
    alternatives: alternatives ?? this.alternatives,
    primaryDirectory: clearPrimaryDirectory
        ? null
        : (primaryDirectory ?? this.primaryDirectory),
  );

  @override
  bool operator ==(Object other) =>
      other is SkillAcquireSpec &&
      kind == other.kind &&
      package == other.package &&
      primaryDirectory == other.primaryDirectory &&
      _listEquals(alternatives, other.alternatives);

  @override
  int get hashCode => Object.hash(
    kind,
    package,
    primaryDirectory,
    Object.hashAll(alternatives),
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Stable script skill id from package URL: `script:<host>/<path-basename>`.
String skillScriptIdFromPackageUrl(String? package) {
  if (package == null || package.trim().isEmpty) {
    return 'script:unknown';
  }
  final uri = Uri.tryParse(package.trim());
  if (uri == null || uri.host.isEmpty) {
    return 'script:unknown';
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final basename = segments.isEmpty ? 'unknown' : segments.last;
  return 'script:${uri.host}/$basename';
}
