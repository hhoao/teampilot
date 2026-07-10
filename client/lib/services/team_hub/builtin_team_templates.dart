import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';

/// Canonical key prefix for templates shipped inside TeamPilot (not from a
/// remote TeamHub registry).
const kBuiltinTeamHubKeyPrefix = 'teampilot/builtin';

/// Portable Superpowers skill ref shared by Team Hub + Expert Hub builtins.
SkillDependencyRef superpowersSkillDep(String slug, String displayName) =>
    SkillDependencyRef(
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/$slug',
      name: displayName,
    );

String _builtinExpertKey(String slug) => '$kBuiltinTeamHubKeyPrefix/$slug';

/// Four-member mixed team that mirrors the Superpowers workflow with a
/// delegate-only lead: lead (pure bus dispatch) → architect (brainstorm gate +
/// plan) → builder (execute with TDD, parallel-dispatch) → reviewer
/// (traceability + verification). Members coordinate only via teammate-bus MCP.
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
  updatedAt: 1_781_654_400_000,
  cli: CliTool.claude,
  teamMode: TeamMode.mixed,
  roster: [
    TeamRosterSlot(
      id: 'team-lead',
      expertKey: _builtinExpertKey('superpowers-lead'),
    ),
    TeamRosterSlot(
      id: 'architect',
      expertKey: _builtinExpertKey('superpowers-architect'),
    ),
    TeamRosterSlot(
      id: 'builder',
      expertKey: _builtinExpertKey('superpowers-builder'),
    ),
    TeamRosterSlot(
      id: 'reviewer',
      expertKey: _builtinExpertKey('superpowers-reviewer'),
    ),
  ],
  skillDeps: [
    superpowersSkillDep('using-superpowers', 'Using Superpowers'),
    superpowersSkillDep('brainstorming', 'Brainstorming'),
    superpowersSkillDep('writing-plans', 'Writing Plans'),
    superpowersSkillDep('executing-plans', 'Executing Plans'),
    superpowersSkillDep('test-driven-development', 'Test-Driven Development'),
    superpowersSkillDep(
      'verification-before-completion',
      'Verification Before Completion',
    ),
    superpowersSkillDep('requesting-code-review', 'Requesting Code Review'),
    superpowersSkillDep(
      'dispatching-parallel-agents',
      'Dispatching Parallel Agents',
    ),
  ],
);

List<DiscoverableTeam> builtInTeamTemplates() => [kSuperpowersTrioTeamTemplate];
