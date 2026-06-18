#!/usr/bin/env python3
"""Migrate tests from CliDataLayout to RuntimeLayout / WorkspaceLayout."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "test"

IMPORT_OLD = "import 'package:teampilot/services/cli/cli_data_layout.dart';"
IMPORT_NEW = "import 'package:teampilot/services/storage/runtime_layout.dart';"

SUBS = [
    ("CliDataLayout", "RuntimeLayout"),
    ("cliLayoutDefaultTools", "runtimeLayoutDefaultTools"),
    ("appProjectsDirForTeampilotRoot", "workspaceDirForTeampilotRoot"),
    ("appProjectsDir", "workspaceDir"),
    ("configProfilesDir", "cliDefaultsDir"),
    ("ensureStandaloneProjectInheritsApp", "ensureProjectConfigInheritsApp"),
    ("ensureStandaloneSessionInheritsProject", "ensureSessionRuntimeInheritsProject"),
    ("provisionStandaloneSessionPluginsFromProject", "provisionSessionPluginsFromProject"),
    ("standaloneProjectSessionToolDir(", "sessionRuntimeToolDir("),
    ("standaloneProjectToolDir(", "projectConfigToolDir("),
    ("standaloneProjectPluginsDir(", "projectConfigPluginsDir("),
    ("standaloneProjectMcpDir(", "projectConfigMcpDir("),
    ("standaloneProjectMcpServersFile(", "projectConfigMcpServersFile("),
    ("runtimeSessionId:", "sessionId:"),
    ("join(basePath, 'projects')", "join(basePath, 'workspace')"),
    ("join(tmp.path, 'projects')", "join(tmp.path, 'workspace')"),
    ("'${tmp.path}/projects'", "'${tmp.path}/workspace'"),
    ("posix.join(teampilotRoot, 'projects')", "posix.join(teampilotRoot, 'workspace')"),
]

# config-profiles -> cli-defaults / teams-runtime (order matters)
PATH_SUBS = [
    ("config-profiles/teams/", "teams-runtime/"),
    ("config-profiles/standalone/projects/", "workspace/projects/"),
    ("config-profiles/", "cli-defaults/"),
    ("'/projects'", "'/workspace'"),
]

MEMBER_TOOL_RE = re.compile(
    r"\.memberToolDir\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*\)"
)

PROVISION_RE = re.compile(
    r"\.provisionMemberPluginsFromTeam\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*\)"
)


def migrate_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    original = text
    text = text.replace(IMPORT_OLD, IMPORT_NEW)
    for old, new in SUBS:
        text = text.replace(old, new)
    for old, new in PATH_SUBS:
        text = text.replace(old, new)

  # memberToolDir(teamId, sessionId, tool) -> sessionRuntimeToolDir('project-1', sessionId, tool)
    text = MEMBER_TOOL_RE.sub(
        r".sessionRuntimeToolDir('project-1', '\2', '\3')", text
    )
    # default project id 'p' for generic layout tests; override in session tests via project-1
    text = PROVISION_RE.sub(
        r".provisionSessionPluginsFromIdentity('project-1', '\2', '\1', '\3')",
        text,
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> None:
    n = sum(1 for p in ROOT.rglob("*.dart") if migrate_file(p))
    print(f"updated {n} files")


if __name__ == "__main__":
    main()
