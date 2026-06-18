import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import '../session/member_role_provision.dart';
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
    this.isFreshConversation = true,
  });

  final TeamIdentity team;
  final TeamMemberConfig member;
  final String? sessionTeam;
  final String? workingDirectory;
  final List<String> additionalDirectories;
  final String? fixedSessionId;
  final String? resumeSessionId;
  final String? settingsPath;
  final String? appendSystemPromptFile;
  final bool useWslPaths;

  /// Whether this is the conversation's first launch (no prior history), so
  /// CLIs that inject identity as the opening prompt should seed it. Even a
  /// `--resume` into a freshly pre-allocated empty session is "fresh". See
  /// `docs/session-resume-architecture.md`.
  final bool isFreshConversation;

  String get teamName => sessionTeam ?? team.name.trim();
  String get memberDisplayName => member.name.trim();

  /// CLI roster / `--agent-name` key ([TeamMemberConfig.id]).
  String get memberCliId => member.id.trim();

  CliLaunchContext copyWith({
    TeamIdentity? team,
    TeamMemberConfig? member,
    String? sessionTeam,
    String? workingDirectory,
    List<String>? additionalDirectories,
    String? fixedSessionId,
    String? resumeSessionId,
    String? settingsPath,
    String? appendSystemPromptFile,
    bool? useWslPaths,
    bool? isFreshConversation,
  }) {
    return CliLaunchContext(
      team: team ?? this.team,
      member: member ?? this.member,
      sessionTeam: sessionTeam ?? this.sessionTeam,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      additionalDirectories: additionalDirectories ?? this.additionalDirectories,
      fixedSessionId: fixedSessionId ?? this.fixedSessionId,
      resumeSessionId: resumeSessionId ?? this.resumeSessionId,
      settingsPath: settingsPath ?? this.settingsPath,
      appendSystemPromptFile:
          appendSystemPromptFile ?? this.appendSystemPromptFile,
      useWslPaths: useWslPaths ?? this.useWslPaths,
      isFreshConversation: isFreshConversation ?? this.isFreshConversation,
    );
  }
}

abstract interface class CliToolAdapter implements LaunchArgsCapability {
  @override
  List<String> buildArguments(CliLaunchContext context);
}

class FlashskyaiCliToolAdapter implements CliToolAdapter {
  const FlashskyaiCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final mixed = context.team.teamMode == TeamMode.mixed;
    final args = <String>[
      ..._buildSessionPrefixArgs(context),
      if (!mixed) ...[
        '--team',
        context.teamName,
        '--member',
        context.memberCliId,
      ],
    ];

    final loop = context.team.loop;
    if (!mixed && loop != null) {
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
    final mixed = context.team.teamMode == TeamMode.mixed;
    final args = <String>[
      ..._buildSessionPrefixArgs(context, includeWorkingDirectory: false),
      if (!mixed) ...[
        '--team-name',
        context.teamName,
        '--agent-name',
        context.memberCliId,
        '--agent-id',
        TeamMemberNaming.cliAgentId(
          memberId: context.memberCliId,
          cliTeamName: context.teamName,
        ),
      ],
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

/// OpenAI Codex CLI (`codex` TUI). Identity is injected via `$CODEX_HOME/AGENTS.md`
/// and team-bus wiring via `$CODEX_HOME/config.toml` (see [CodexConfigProfileCapability]),
/// so — unlike flashskyai — codex takes none of `--team`/`--member`/`--session-id`/
/// `--append-system-prompt-file`. Working dir is `--cd`, model is `-m`. codex
/// cannot be told an id at creation; to resume we replay the id captured from
/// its isolated `$CODEX_HOME/sessions` via the `resume <id>` subcommand (see
/// docs/session-resume-architecture.md).
class CodexCliToolAdapter implements CliToolAdapter {
  const CodexCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final mixed = context.team.teamMode == TeamMode.mixed;
    final args = <String>[];

    // `resume <id>` must lead the argv (it is a subcommand). codex ignores any
    // create-time id, so there is no fresh-session prefix.
    final resume = context.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['resume', resume]);
    }

    final wd = context.workingDirectory ?? '';
    if (wd.isNotEmpty) {
      args.addAll(['--cd', _normalizePathForCli(wd, context.useWslPaths)]);
    }

    final model = member.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['-m', model]);
    }

    if (member.dangerouslySkipPermissions) {
      args.add('--dangerously-bypass-approvals-and-sandbox');
    }
    // Mixed mode provisions a self-trusted Stop hook (idle shim) into CODEX_HOME;
    // bypass the interactive hook-trust prompt for this invocation.
    if (mixed) {
      args.add('--dangerously-bypass-hook-trust');
    }

    _addExtraArgs(args, context.team.extraArgs);
    _addExtraArgs(args, member.extraArgs);

    return args;
  }
}

/// Cursor CLI (`cursor-agent` TUI). No `--system-prompt` flag, so member
/// identity is seeded as the leading positional prompt on a fresh launch
/// (route B); on `--resume` it already lives in the conversation history and is
/// not re-passed. Config isolation is via `$CURSOR_CONFIG_DIR`
/// (see [CursorConfigProfileCapability]). Working dir is `--workspace`, model
/// `--model`, skip-permissions `--force`. Session id is allocated out-of-band
/// (`cursor-agent create-chat`) and replayed through [resumeSessionId].
class CursorCliToolAdapter implements CliToolAdapter {
  const CursorCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final mixed = context.team.teamMode == TeamMode.mixed;
    final args = <String>[];

    final wd = context.workingDirectory ?? '';
    if (wd.isNotEmpty) {
      args.addAll([
        '--workspace',
        _normalizePathForCli(wd, context.useWslPaths),
      ]);
    }

    final resume = context.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['--resume', resume]);
    }

    final model = member.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }

    if (member.dangerouslySkipPermissions) {
      args.add('--force');
    }

    // Mixed mode registers a localhost teammate-bus MCP server; auto-approve
    // the server trust prompt (tool-level allowlist is in cli-config.json).
    if (mixed) {
      args.add('--approve-mcps');
    }

    _addExtraArgs(args, context.team.extraArgs);
    _addExtraArgs(args, member.extraArgs);

    // Route B: seed identity as the initial prompt only on a fresh standalone
    // conversation (including a freshly pre-allocated empty chat — see
    // docs/session-resume-architecture.md). In mixed mode the fake HOME role
    // rule owns identity, so skip it.
    if (context.isFreshConversation && !mixed) {
      final rolePrompt = MemberRoleProvision.composeRolePrompt(
        member: member,
        forceTeamLeadDelegateMode: context.team.forceTeamLeadDelegateMode,
        mixed: mixed,
      ).trim();
      if (rolePrompt.isNotEmpty) {
        args.add(rolePrompt);
      }
    }

    return args;
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
