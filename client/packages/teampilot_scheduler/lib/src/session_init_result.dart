final class SessionSpawnSpec {
  const SessionSpawnSpec({
    required this.executable,
    required this.argv,
    required this.env,
    required this.cwd,
  });
  final String executable;
  final List<String> argv;
  final Map<String, String> env;
  final String cwd;
}

final class SessionInitResult {
  const SessionInitResult({
    required this.spawn,
    this.warnings = const [],
    this.nativeSessionIdToPersist,
  });
  final SessionSpawnSpec spawn;
  final List<String> warnings;
  final String? nativeSessionIdToPersist;
}
