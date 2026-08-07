import '../cli_capability.dart';

/// How a CLI references a skill in prompt text.
///
/// Claude Code and friends invoke a skill as `/skill-name`; Codex uses the `$`
/// prefix and namespaces plugin skills as `$<plugin>:<skill>` (e.g.
/// `$superpowers:using-git-worktrees`). Each CLI declares its own syntax so
/// skill insertion (compose `/` menu) stays free of `if (cli == …)` branching.
abstract interface class SkillInvocationSyntaxCapability
    implements CliCapability {
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
class DefaultSkillInvocationSyntaxCapability
    implements SkillInvocationSyntaxCapability {
  const DefaultSkillInvocationSyntaxCapability({this.leadingSeparator = ''});

  final String leadingSeparator;

  @override
  String get skillInvocationPrefix => '/';

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      '$leadingSeparator/$skillName';
}

/// opencode's slash commands are only recognized when the `/` is preceded by
/// whitespace, so a space is inserted before the reference.
final class OpencodeSkillInvocationSyntaxCapability
    extends DefaultSkillInvocationSyntaxCapability {
  const OpencodeSkillInvocationSyntaxCapability()
    : super(leadingSeparator: ' ');
}

/// Codex: `$superpowers:using-git-worktrees`.
final class CodexSkillInvocationSyntaxCapability
    implements SkillInvocationSyntaxCapability {
  const CodexSkillInvocationSyntaxCapability();

  @override
  String get skillInvocationPrefix => r'$';

  @override
  String skillInvocationText(String skillName, {String? namespace}) {
    final ns = namespace != null && namespace.trim().isNotEmpty
        ? '$namespace:'
        : '';
    return r'$' '$ns$skillName';
  }
}
