/// Result of probing the host for an extension's underlying tool.
class ExtensionProbe {
  const ExtensionProbe({
    required this.found,
    this.executablePath,
    this.version,
    this.satisfiesMinVersion = true,
    this.missingRequirements = const [],
  });

  final bool found;
  final String? executablePath;
  final String? version;
  final bool satisfiesMinVersion;
  final List<String> missingRequirements;

  bool get isReady =>
      found && satisfiesMinVersion && missingRequirements.isEmpty;
}
