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
