/// Shipped `teampilot-catalog` skill body. Must match
/// `lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md`.
const teampilotCatalogSkillMd = '''
---
name: teampilot-catalog
description: Install, import, create, update, or remove TeamPilot skills, plugins, MCP servers, and automations. Use when the user wants to add, install, find, or import a skill, plugin, or MCP; search skills.sh or a marketplace; run npx or an install script; schedule a recurring task or reminder; or mentions superpowers, context7, or community agent skills. Never write to ~/.claude/skills, .claude/skills, or ~/.claude.json — those paths are wiped on the next TeamPilot session start.
---

# TeamPilot catalog

Use the `teampilot` MCP to search, install, import, create, update, unbind, or delete TeamPilot skills, plugins, and MCP servers, and to list, create, update, delete, enable/disable, or run automations. Skill/plugin/MCP changes bind to the current workspace and take effect after the user reconnects the session; automation changes take effect immediately.

## Workflow

1. Search first with `search_skills`, `search_plugins`, or `search_mcp`. Match an existing catalog entry before installing. Do not guess a git URL.
2. Remote source, marketplace, or `script_url` → `install_skill` / `install_plugin` / `install_mcp`.
3. A directory the agent already produced with Bash, `npx`, or an install script → `import_skill` / `import_plugin`. MCP JSON fragments → `import_mcp`.
4. Write from scratch → `create_skill` (plugins cannot be created from scratch). Change installed files → `update_*`. Remove from this workspace only → `unbind_*`. Remove from the TeamPilot library → `delete_*`.
5. Recurring or scheduled work → `create_automation` (created disabled; the user enables it in Automations, or you call `update_automation` with `enabled:true` only when asked). Read with `read_automation`, test with `run_automation`, clean up with `delete_automation`.
6. On success, tell the user to reconnect the session using the tool result `message`. The current session does not hot-load the change.
7. Never write to `~/.claude/skills`, `.claude/skills`, or `~/.claude.json`. Do not `git clone` into `~/.claude`, treat a project `.mcp.json` as installed into TeamPilot, or treat `claude mcp add` as done.

TeamPilot stores the global library under the application data directory and binds ids in workspace project config. Isolation wipes `~/.claude` paths on the next session start.
''';
