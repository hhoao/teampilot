/// Script execution dialect for hook files and inline installer scripts.
enum HostScriptDialect {
  bash,
  powershell,
}

extension HostScriptDialectX on HostScriptDialect {
  String get scriptExtension => switch (this) {
    HostScriptDialect.bash => '.sh',
    HostScriptDialect.powershell => '.ps1',
  };
}
