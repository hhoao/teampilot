import '../models/team_config.dart';

class CliLaunchContext {
  const CliLaunchContext({
    required this.team,
    required this.member,
    this.sessionTeam,
    this.workingDirectory,
    this.additionalDirectories = const [],
    this.fixedSessionId,
    this.resumeSessionId,
    this.useWslPaths = false,
  });

  final TeamConfig team;
  final TeamMemberConfig member;
  final String? sessionTeam;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final String? fixedSessionId;
  final String? resumeSessionId;
  final bool useWslPaths;

  String get teamName => sessionTeam ?? team.name.trim();
  String get memberName => member.name.trim();
}

abstract interface class CliToolAdapter {
  List<String> buildArguments(CliLaunchContext context);
}

class CliToolAdapterRegistry {
  const CliToolAdapterRegistry({
    this.flashskyai = const FlashskyaiCliToolAdapter(),
    this.claude = const ClaudeCodeCliToolAdapter(),
  });

  final CliToolAdapter flashskyai;
  final CliToolAdapter claude;

  CliToolAdapter forCli(TeamCli cli) {
    return switch (cli) {
      TeamCli.claude => claude,
      TeamCli.flashskyai || TeamCli.codex => flashskyai,
    };
  }
}

class FlashskyaiCliToolAdapter implements CliToolAdapter {
  const FlashskyaiCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final args = <String>[
      ..._buildSessionPrefixArgs(context),
      '--team',
      context.teamName,
      '--member',
      context.memberName,
    ];

    final loop = context.team.loop;
    if (loop != null) {
      args.addAll(['--loop', loop ? 'true' : 'false']);
    }

    final member = context.member;
    if (member.provider.trim().isNotEmpty) {
      args.addAll(['--provider', member.provider.trim()]);
    }
    if (member.model.trim().isNotEmpty) {
      args.addAll(['--model', member.model.trim()]);
    }
    if (member.agent.trim().isNotEmpty) {
      args.addAll(['--agent', member.agent.trim()]);
    }
    if (member.dangerouslySkipPermissions) {
      args.add('--dangerously-skip-permissions');
    }
    _addExtraArgs(args, context.team.extraArgs);
    _addExtraArgs(args, member.extraArgs);

    return args;
  }
}

class ClaudeCodeCliToolAdapter implements CliToolAdapter {
  const ClaudeCodeCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final args = <String>[
      ..._buildSessionPrefixArgs(context),
      '--agent-teams',
      '--team-name',
      context.teamName,
      '--agent-name',
      context.memberName,
      '--agent-id',
      '${context.memberName}@${context.teamName}',
    ];

    if (member.model.trim().isNotEmpty) {
      args.addAll(['--model', member.model.trim()]);
    }
    if (member.dangerouslySkipPermissions) {
      args.add('--dangerously-skip-permissions');
    }
    _addExtraArgs(args, context.team.extraArgs);
    _addExtraArgs(args, member.extraArgs);

    return args;
  }
}

List<String> _buildSessionPrefixArgs(CliLaunchContext context) {
  final args = <String>[];
  final resume = context.resumeSessionId?.trim() ?? '';
  final fixed = context.fixedSessionId?.trim() ?? '';
  if (resume.isNotEmpty) {
    args.addAll(['--resume', resume]);
  } else if (fixed.isNotEmpty) {
    args.addAll(['--session-id', fixed]);
  }
  final wd = context.workingDirectory ?? '';
  if (wd.isNotEmpty) {
    args.addAll(['--dir', _normalizePathForCli(wd, context.useWslPaths)]);
  }
  for (final path in context.additionalDirectories) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty) {
      args.addAll([
        '--add-dir',
        _normalizePathForCli(trimmed, context.useWslPaths),
      ]);
    }
  }
  return args;
}

void _addExtraArgs(List<String> args, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isNotEmpty) {
    args.addAll(_splitArgs(trimmed));
  }
}

List<String> _splitArgs(String input) {
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

String _normalizePathForCli(String path, bool useWslPaths) {
  if (!useWslPaths) return path;
  return _windowsPathToWsl(path) ?? path;
}

String? _windowsPathToWsl(String path) {
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
