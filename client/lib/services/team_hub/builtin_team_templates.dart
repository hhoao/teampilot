import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';

/// Canonical key prefix for templates shipped inside TeamPilot (not from a
/// remote TeamHub registry).
const kBuiltinTeamHubKeyPrefix = 'teampilot/builtin';

SkillDependencyRef _superpowersSkill(String slug, String displayName) =>
    SkillDependencyRef(
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/$slug',
      name: displayName,
    );

/// Three-member mixed team that mirrors the Superpowers workflow:
/// lead (brainstorm gate + bus dispatch) → builder (plan + execute) → reviewer
/// (traceability + verification). Members coordinate only via teammate-bus MCP.
final DiscoverableTeam kSuperpowersTrioTeamTemplate = DiscoverableTeam(
  key: '$kBuiltinTeamHubKeyPrefix/superpowers-trio',
  name: 'Superpowers Trio',
  description:
      'A mixed-CLI team that runs the Superpowers pipeline end-to-end: '
      'the lead holds the brainstorm gate and dispatches bus tasks; the builder '
      'writes plans and executes with TDD; the reviewer validates traceability '
      '(user ask ↔ design ↔ plan ↔ diff ↔ test evidence) before sign-off. '
      'Configure per-member CLI and models after cloning — coordination is '
      'always through the teammate bus (wait_for_message / send_message).',
  category: 'Workflow',
  author: 'TeamPilot',
  updatedAt: 1_748_400_000_000, // 2025-05-28 — stable sort bump when edited
  cli: CliTool.flashskyai,
  teamMode: TeamMode.mixed,
  members: [
    DiscoverableTeamMember(
      name: 'team-lead',
      prompt:
          'Run the Superpowers workflow gate: clarify scope, decompose work '
          'into bus tasks with acceptance criteria, assign builder and reviewer, '
          'and synthesize the final user-facing answer. '
          'Do NOT implement code or perform final quality sign-off yourself.',
      playbook:
          'Idle loop: wait_for_message only. On user input, follow '
          'brainstorming if available, confirm the design with the user, then '
          'assign plan+execute to builder and review to reviewer. Track phase '
          'gates (design approved → plan ready → implementation done → review '
          'pass). Use dispatching-parallel-agents when tasks are independent. '
          'Never stand down; escalate blockers to the user.',
    ),
    DiscoverableTeamMember(
      name: 'builder',
      prompt:
          'Turn the approved design into an implementation plan, then execute it '
          'with test-first discipline within assigned scope. '
          'Do NOT expand scope, skip verification commands, or sign off your '
          'own work.',
      playbook:
          'On assignment from the lead: follow writing-plans, then '
          'executing-plans with test-driven-development and systematic-debugging '
          'when stuck. Smallest correct diff; run the suite before '
          'update_task(done). Report changed files and command evidence. On '
          'review failures, fix and resubmit without renegotiating scope.',
    ),
    DiscoverableTeamMember(
      name: 'reviewer',
      prompt:
          'Validate traceability from the user request through approved design, '
          'plan, diff, and test evidence; block on gaps. '
          'Do NOT implement fixes — return actionable findings to builder.',
      playbook:
          'Follow requesting-code-review, receiving-code-review, and '
          'verification-before-completion. Read-only review with file:line '
          'references. Pass only when verification commands were run and output '
          'is attached. update_task with structured pass/fail and blocking '
          'items; never patch code yourself.',
    ),
  ],
  skillDeps: [
    _superpowersSkill('using-superpowers', 'Using Superpowers'),
    _superpowersSkill('brainstorming', 'Brainstorming'),
    _superpowersSkill('writing-plans', 'Writing Plans'),
    _superpowersSkill('executing-plans', 'Executing Plans'),
    _superpowersSkill('test-driven-development', 'Test-Driven Development'),
    _superpowersSkill(
      'verification-before-completion',
      'Verification Before Completion',
    ),
    _superpowersSkill('requesting-code-review', 'Requesting Code Review'),
    _superpowersSkill(
      'dispatching-parallel-agents',
      'Dispatching Parallel Agents',
    ),
  ],
);

/// All team templates bundled with TeamPilot (prepended to remote registry
/// results in [CompositeTeamHubSource]).
List<DiscoverableTeam> builtInTeamTemplates() => [
      kSuperpowersTrioTeamTemplate,
    ];
