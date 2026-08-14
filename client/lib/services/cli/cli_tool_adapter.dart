import '../../models/team_config.dart';
import '../../utils/team/team_member_naming.dart';
import '../session/member_role_provision.dart';

class CliLaunchContext {
  const CliLaunchContext({
    required this.team,
    required this.member,
    this.sessionTeam,
    this.workingDirectory,
    this.additionalDirectories = const [],
    this.fixedSessionId,
    this.resumeSessionId,
    this.settingsPath,
    this.appendSystemPromptFile,
    this.useWslPaths = false,
    this.nativeAgentTeam,
  });

  final TeamProfile team;
  final TeamMemberConfig member;
  final String? sessionTeam;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final String? fixedSessionId;
  final String? resumeSessionId;
  final String? settingsPath;
  final String? appendSystemPromptFile;
  final bool useWslPaths;

  /// When set, forces Claude `--team-name` / `--agent-name` / `--agent-id`.
  ///
  /// Personal/simple builds a 1-member synthetic [TeamMode.native] profile for
  /// argv plumbing; callers must pass `false` so Claude does not enter agent
  /// "manual mode" (multi-call loops). `null` keeps legacy derive: on when
  /// [team] is not mixed.
  final bool? nativeAgentTeam;

  String get teamName => sessionTeam ?? team.name.trim();
  String get memberDisplayName => member.name.trim();

  /// CLI roster / `--agent-name` key ([TeamMemberConfig.id]).
  String get memberCliId => member.id.trim();

  /// Whether Claude native agent-team flags should be emitted.
  bool get usesNativeAgentTeam =>
      nativeAgentTeam ?? team.teamMode != TeamMode.mixed;

  CliLaunchContext copyWith({
    TeamProfile? team,
    TeamMemberConfig? member,
    String? sessionTeam,
    String? workingDirectory,
    List<String>? additionalDirectories,
    String? fixedSessionId,
    String? resumeSessionId,
    String? settingsPath,
    String? appendSystemPromptFile,
    bool? useWslPaths,
    bool? nativeAgentTeam,
  }) {
    return CliLaunchContext(
      team: team ?? this.team,
      member: member ?? this.member,
      sessionTeam: sessionTeam ?? this.sessionTeam,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      additionalDirectories:
          additionalDirectories ?? this.additionalDirectories,
      fixedSessionId: fixedSessionId ?? this.fixedSessionId,
      resumeSessionId: resumeSessionId ?? this.resumeSessionId,
      settingsPath: settingsPath ?? this.settingsPath,
      appendSystemPromptFile:
          appendSystemPromptFile ?? this.appendSystemPromptFile,
      useWslPaths: useWslPaths ?? this.useWslPaths,
      nativeAgentTeam: nativeAgentTeam ?? this.nativeAgentTeam,
    );
  }
}

abstract interface class CliToolAdapter {
  List<String> buildArguments(CliLaunchContext context);
}

List<String> buildSessionPrefixArgs(
  CliLaunchContext context, {
  bool includeWorkingDirectory = true,
}) {
  final args = <String>[];
  final resume = context.resumeSessionId?.trim() ?? '';
  final fixed = context.fixedSessionId?.trim() ?? '';
  if (resume.isNotEmpty) {
    args.addAll(['--resume', resume]);
  } else if (fixed.isNotEmpty) {
    args.addAll(['--session-id', fixed]);
  }
  final wd = context.workingDirectory ?? '';
  if (includeWorkingDirectory && wd.isNotEmpty) {
    args.addAll(['--dir', normalizePathForCli(wd, context.useWslPaths)]);
  }
  for (final path in context.additionalDirectories) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty) {
      args.addAll([
        '--add-dir',
        normalizePathForCli(trimmed, context.useWslPaths),
      ]);
    }
  }
  return args;
}

void addExtraArgs(List<String> args, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isNotEmpty) {
    args.addAll(splitArgs(trimmed));
  }
}

List<String> splitArgs(String input) {
  final args = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaping = false;

  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == r'\') {
      escaping = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        args.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }

  if (escaping) {
    buffer.write(r'\');
  }
  if (buffer.isNotEmpty) {
    args.add(buffer.toString());
  }
  return args;
}

String normalizePathForCli(String path, bool useWslPaths) {
  if (!useWslPaths) return path;
  return windowsPathToWsl(path) ?? path;
}

String? windowsPathToWsl(String path) {
  final trimmed = path.trim();
  final uncMatch = RegExp(
    r'^\\+(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed.replaceAll('/', r'\'));
  if (uncMatch != null) {
    return '/${uncMatch.group(1)!.replaceAll(r'\', '/')}';
  }

  final match = RegExp(r'^([a-zA-Z]):[\\/]*(.*)$').firstMatch(trimmed);
  if (match == null) return null;
  final drive = match.group(1)!.toLowerCase();
  final rest = match.group(2)!.replaceAll('\\', '/');
  return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
}
