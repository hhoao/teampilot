import '../core/turns.dart';
import 'simple_3turn.dart' show simpleScriptApiKey;

export 'simple_3turn.dart' show simpleScriptApiKey;

/// PTY / bubble marker after catalog MCP search + create succeed.
const markCatalogOk = 'MARK_CATALOG_OK';

/// Stable create_skill payload used by the Claude L2 catalog cell.
const catalogL2SkillName = 'L2 Catalog Skill';
const catalogL2SkillDirectory = 'l2-catalog-skill';
const catalogL2SkillBody = 'Created by Claude via catalog MCP.';

/// Logical `catalog.*` toolRefs (NOT raw `mcp__…` wire names). Wire mapping is
/// applied later via [CliTestProfile.toolName] / [ToolNameResolver].
Map<String, MockScenario> catalogMcpSimpleClaudeScenarios() => {
  simpleScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(
        id: 'tu_search',
        toolRef: 'catalog.search_skills',
        input: {'query': 'catalog'},
      ),
      ToolUseTurn(
        id: 'tu_create',
        toolRef: 'catalog.create_skill',
        input: {
          'name': catalogL2SkillName,
          'directory': catalogL2SkillDirectory,
          'body': catalogL2SkillBody,
        },
      ),
      const TextTurn(markCatalogOk),
    ],
  ),
};
