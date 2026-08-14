import '../cli_capability.dart';

/// How a resource kind is represented inside a CLI's CONFIG_DIR.
enum ResourceRepresentation { linkedDirectory, mergedJsonEntry }

/// SkillHub contract: how skills land in a CLI's CONFIG_DIR and how they are
/// invoked in prompt text. Contains NO provisioning logic — the shared
/// materializer does the work; this just describes the target shape.
abstract interface class SkillCapability implements CliCapability {
  /// Subdirectory (relative to the CONFIG_DIR) where skill entries live
  /// (e.g. 'skills', 'skill', 'skills-cursor').
  String get skillsSubdir;

  /// How skills are represented inside the CLI's CONFIG_DIR.
  ResourceRepresentation get skillsRepresentation;

  /// The character that prefixes a skill invocation (`/` for Claude, `$` for
  /// Codex). Also opens the compose skill menu alongside `/`.
  String get skillInvocationPrefix;

  /// Renders the prompt text that invokes [skillName]. [namespace] is the
  /// plugin name when the skill ships inside a plugin bundle.
  String skillInvocationText(String skillName, {String? namespace});
}

/// Default: Claude-style `/skill-name` invocation, no namespace.
///
/// [leadingSeparator] is prepended before the prefix when a CLI only
/// recognizes a slash command after whitespace (opencode) — inserting
/// ` /skill-name` keeps the `/` from gluing to the preceding text.
class DefaultSkillInvocationSyntaxCapability {
  const DefaultSkillInvocationSyntaxCapability({this.leadingSeparator = ''});

  final String leadingSeparator;

  String get skillInvocationPrefix => '/';

  String skillInvocationText(String skillName, {String? namespace}) =>
      '$leadingSeparator/$skillName';
}
