import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import 'registry/capabilities/launch_args_capability.dart';

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
  });

  final TeamConfig team;
  final TeamMemberConfig member;
  final String? sessionTeam;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final String? fixedSessionId;
  final String? resumeSessionId;
  final String? settingsPath;
  final String? appendSystemPromptFile;
  final bool useWslPaths;

  String get teamName => sessionTeam ?? team.name.trim();
  String get memberDisplayName => member.name.trim();

  /// CLI roster / `--agent-name` key ([TeamMemberConfig.id]).
  String get memberCliId => member.id.trim();
}

abstract interface class CliToolAdapter implements LaunchArgsCapability {
  @override
  List<String> buildArguments(CliLaunchContext context);
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
      context.memberCliId,
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

    final appendFile = context.appendSystemPromptFile?.trim() ?? '';
    if (appendFile.isNotEmpty) {
      args.addAll(['--append-system-prompt-file', appendFile]);
    }

    return args;
  }
}

class ClaudeCodeCliToolAdapter implements CliToolAdapter {
  const ClaudeCodeCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final args = <String>[
      ..._buildSessionPrefixArgs(context, includeWorkingDirectory: false),
      '--team-name',
      context.teamName,
      '--agent-name',
      context.memberCliId,
      '--agent-id',
      TeamMemberNaming.cliAgentId(
        memberId: context.memberCliId,
        cliTeamName: context.teamName,
      ),
    ];

    if (member.model.trim().isNotEmpty) {
      args.addAll(['--model', member.model.trim()]);
    }
    final settings = context.settingsPath?.trim() ?? '';
    if (settings.isNotEmpty) {
      args.addAll(['--settings', settings]);
    }
    final appendFile = context.appendSystemPromptFile?.trim() ?? '';
    if (appendFile.isNotEmpty) {
      args.addAll(['--append-system-prompt-file', appendFile]);
    }
    if (member.dangerouslySkipPermissions) {
      args.add('--dangerously-skip-permissions');
    }
    _addExtraArgs(args, context.team.extraArgs);
    _addExtraArgs(args, member.extraArgs);

    return args;
  }
}

/// opencode TUI（bare `opencode`，默认命令）。工作目录走进程 cwd；
/// 模型用 `provider/model` 形式；resume 用 `--session`（opencode 无「指定 id 新建」flag）。
class OpencodeCliToolAdapter implements CliToolAdapter {
  const OpencodeCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final args = <String>[];

    final resume = context.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['--session', resume]);
    }

    final model = _opencodeModel(member);
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }

    final agent = member.agent.trim();
    if (agent.isNotEmpty) {
      args.addAll(['--agent', agent]);
    }

    _addExtraArgs(args, context.team.extraArgs);
    _addExtraArgs(args, member.extraArgs);

    return args;
  }

  /// opencode 期望 `provider/model`；缺 provider 时退回裸 model。
  String _opencodeModel(TeamMemberConfig member) {
    final provider = member.provider.trim();
    final model = member.model.trim();
    if (model.isEmpty) return '';
    if (provider.isEmpty) return model;
    return '$provider/$model';
  }
}

List<String> _buildSessionPrefixArgs(
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
