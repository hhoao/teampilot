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

/// Four-member mixed team that mirrors the Superpowers workflow with a
/// delegate-only lead: lead (pure bus dispatch) → architect (brainstorm gate +
/// plan) → builder (execute with TDD, parallel-dispatch) → reviewer
/// (traceability + verification). Members coordinate only via teammate-bus MCP.
///
/// The lead's delegate-only hook blocks Skill/workflow/Write/Edit/Bash, so it
/// can neither brainstorm nor dispatch parallel agents itself — those duties
/// live on the architect and builder, who are unrestricted.
final DiscoverableTeam kSuperpowersTrioTeamTemplate = DiscoverableTeam(
  key: '$kBuiltinTeamHubKeyPrefix/superpowers-trio',
  name: 'Superpowers Quartet',
  description:
      'A mixed-CLI team that runs the Superpowers pipeline end-to-end: '
      'the lead is dispatch-only and routes bus tasks; the architect holds the '
      'brainstorm gate and writes the plan; the builder executes with TDD and '
      'dispatches parallel agents for independent tasks; the reviewer validates '
      'traceability (user ask ↔ design ↔ plan ↔ diff ↔ test evidence) before '
      'sign-off. Configure per-member CLI and models after cloning — '
      'coordination is always through the teammate bus '
      '(wait_for_message / send_message).',
  category: 'Workflow',
  author: 'TeamPilot',
  updatedAt: 1_781_654_400_000, // 2026-06-17 — stable sort bump when edited
  cli: CliTool.flashskyai,
  teamMode: TeamMode.mixed,
  members: [
    DiscoverableTeamMember(
      name: 'team-lead',
      prompt:
          'Coordinate the Superpowers pipeline as a pure dispatcher: receive '
          'the user request, decompose it into bus tasks with acceptance '
          'criteria, route work between architect, builder, and reviewer, relay '
          'the architect\'s clarifying questions back to the user, track phase '
          'gates, and synthesize the final user-facing answer. '
          'Do NOT brainstorm, write plans, implement code, or review — '
          'delegate-only mode blocks those tools in this tab anyway.',
      playbook:
          'Idle loop: wait_for_message only. Enqueue work with add_tasks and '
          'ROUTE every task by required_capabilities to the member TYPE (its '
          'name) so only that role can claim it — never leave a task untagged '
          '(untagged work is claimable by anyone, including the reviewer): '
          'design+plan → required_capabilities ["architect"]; implementation → '
          '["builder"]; review → ["reviewer"] AND depends_on the implementation '
          'task ids, so review unlocks only after the build is done. Honor '
          'phase gates (design approved → plan ready → implementation done → '
          'review pass): do not enqueue implementation before the plan is '
          'ready, nor a review task before its implementation tasks exist. Use '
          'send_message only to relay clarifying questions and blockers between '
          'members and the user, and update_task to track gates. Never stand down; '
          'escalate blockers to the user.',
    ),
    DiscoverableTeamMember(
      name: 'architect',
      prompt:
          'Own the design and planning phases the lead cannot run: clarify '
          'scope through brainstorming with the user, lock an approved design, '
          'then turn it into an implementation plan with acceptance criteria. '
          'Do NOT implement production code or expand scope — hand the approved '
          'design and plan back to the lead for dispatch.',
      playbook:
          'On assignment from the lead: follow brainstorming, surfacing '
          'clarifying questions back through the lead to the user until the '
          'design is approved, then writing-plans. Deliver a phased plan the '
          'builder can execute as independent tasks where possible. Report the '
          'approved design and plan via update_task; never write production '
          'code.',
    ),
    DiscoverableTeamMember(
      name: 'builder',
      prompt:
          'Turn the architect\'s approved plan into working code with '
          'test-first discipline within assigned scope. '
          'Do NOT expand scope, skip verification commands, or sign off your '
          'own work.',
      playbook:
          'On assignment from the lead: follow executing-plans with '
          'test-driven-development and systematic-debugging when stuck. When the '
          'plan has independent tasks, use dispatching-parallel-agents to run '
          'them concurrently. Smallest correct diff; run the suite before '
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
List<DiscoverableTeam> builtInTeamTemplates() => [kSuperpowersTrioTeamTemplate];
