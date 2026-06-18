#!/usr/bin/env python3
"""Rebuild service file imports from git HEAD with correct relative paths."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

CLIENT = Path(__file__).resolve().parent.parent
SERVICES = CLIENT / "lib" / "services"
REPO = CLIENT.parent

FILE_TO_SUBDIR: dict[str, str] = {
    "app_storage.dart": "storage",
    "runtime_storage_context.dart": "storage",
    "flashskyai_storage_roots.dart": "storage",
    "remote_file_store.dart": "storage",
    "remote_ssh_storage_paths.dart": "storage",
    "remote_home_resolver.dart": "storage",
    "terminal_session.dart": "terminal",
    "terminal_transport.dart": "terminal",
    "terminal_transport_factory.dart": "terminal",
    "terminal_output_buffer.dart": "terminal",
    "terminal_fonts.dart": "terminal",
    "terminal_export.dart": "terminal",
    "terminal_uri_opener.dart": "terminal",
    "local_pty_transport.dart": "terminal",
    "ssh_pty_transport.dart": "terminal",
    "pty_launch_environment.dart": "terminal",
    "session_lifecycle_service.dart": "session",
    "launch_command_builder.dart": "session",
    "remote_flashskyai_command_builder.dart": "session",
    "member_role_provision.dart": "session",
    "cli_executable_validator.dart": "cli",
    "cli_data_layout.dart": "cli",
    "cli_tool_adapter.dart": "cli",
    "cli_tool_locator.dart": "cli",
    "cli_installer_service.dart": "cli",
    "cli_invocation.dart": "cli",
    "flashskyai_cli_locator.dart": "cli",
    "remote_flashskyai_cli_locator.dart": "cli",
    "plugin_manifest_service.dart": "plugin",
    "plugin_repo_git_service.dart": "plugin",
    "plugin_exceptions.dart": "plugin",
    "plugin_external_fetch_service.dart": "plugin",
    "plugin_fetch_service.dart": "plugin",
    "plugin_repo_service.dart": "plugin",
    "plugin_install_service.dart": "plugin",
    "cli_plugin_layout.dart": "plugin",
    "cli_plugin_registry_service.dart": "plugin",
    "cli_plugin_manifest_flavor.dart": "plugin",
    "cli_plugin_provision_cache.dart": "plugin",
    "plugin_repo_disk_cache_service.dart": "plugin",
    "identity_plugin_linker_service.dart": "plugin",
    "skill_repo_service.dart": "skill",
    "skill_fetch_service.dart": "skill",
    "skill_manifest_service.dart": "skill",
    "skill_repo_git_service.dart": "skill",
    "skill_install_service.dart": "skill",
    "skill_repo_disk_cache_service.dart": "skill",
    "skills_sh_service.dart": "skill",
    "team_skill_linker_service.dart": "skill",
    "claude_provider_credentials_service.dart": "provider",
    "config_profile_service.dart": "provider",
    "provider_import_service.dart": "provider",
    "provider_migration_service.dart": "provider",
    "claude_official_provider.dart": "provider",
    "claude_provider_settings_resolver.dart": "provider",
    "tool_config_generator.dart": "provider",
    "llm_config_path_resolver.dart": "provider",
    "team_lead_delegate_settings_merge.dart": "team",
    "team_lead_hook_provisioner.dart": "team",
    "team_lead_settings_merge.dart": "team",
    "team_lead_delegate_hook_provisioner.dart": "team",
    "claude_team_roster_service.dart": "team",
    "rtk_settings_merge.dart": "team",
    "rtk_hook_provisioner.dart": "team",
    "rtk_detector.dart": "team",
    "claude_hook_shell.dart": "team",
    "ssh_profile_connection_tester.dart": "ssh",
    "ssh_client_factory.dart": "ssh",
    "platform_utils.dart": "app",
    "app_update_asset_selector.dart": "app",
    "error_log_service.dart": "app",
    "backend_app_update_service.dart": "app",
    "app_update_service.dart": "app",
    "app_update_installer.dart": "app",
    "onboarding_service.dart": "app",
    "connection_mode_service.dart": "app",
    "flashskyai_agent_catalog_service.dart": "app",
}

BASENAME_TO_PATH = {n: f"{d}/{n}" for n, d in FILE_TO_SUBDIR.items()}
for p in (SERVICES / "io").glob("*.dart"):
    BASENAME_TO_PATH[p.name] = f"io/{p.name}"

IMPORT_RE = re.compile(r"^import\s+.+;\s*$", re.MULTILINE)


def git_head_path(path: Path) -> str:
    rel = path.relative_to(SERVICES)
    if len(rel.parts) > 1 and rel.parts[0] in set(FILE_TO_SUBDIR.values()):
        return f"client/lib/services/{path.name}"
    return f"client/lib/services/{rel.as_posix()}"


def map_import(path: Path, imp: str) -> str:
    if imp.startswith("dart:") or imp.startswith("package:"):
        return imp
    if imp.startswith("../"):
        # was ../lib/... from services/ -> now ../../lib/...
        return "../" + imp
    if imp.endswith(".dart"):
        target = None
        if imp.startswith("io/"):
            target = SERVICES / imp
        elif imp in BASENAME_TO_PATH:
            target = SERVICES / BASENAME_TO_PATH[imp]
        if target:
            try:
                return target.relative_to(path.parent).as_posix()
            except ValueError:
                prefix = os.path.relpath(target.parent, path.parent)
                return f"{prefix}/{target.name}" if prefix != "." else target.name
    return imp


def rebuild(path: Path) -> bool:
    try:
        old = subprocess.check_output(
            ["git", "show", f"HEAD:{git_head_path(path)}"],
            cwd=REPO,
            text=True,
        )
    except subprocess.CalledProcessError:
        return False

    old_imports = [m.group(0) for m in IMPORT_RE.finditer(old)]
    new_imports = []
    for line in old_imports:
        m = re.match(r"^import\s+(['\"])([^'\"]+)(['\"]);", line.strip())
        if not m:
            new_imports.append(line)
            continue
        q, imp, q2 = m.group(1), m.group(2), m.group(3)
        new_imp = map_import(path, imp)
        new_imports.append(f"import {q}{new_imp}{q2};")

    cur = path.read_text(encoding="utf-8")
    # strip all imports from current
    body = IMPORT_RE.sub("", cur).lstrip("\n")
    # strip duplicate blank lines at top
    while body.startswith("\n\n"):
        body = body[1:]

    new_text = "\n".join(new_imports) + "\n\n" + body
    if new_text != cur:
        path.write_text(new_text, encoding="utf-8")
        return True
    return False


def main() -> None:
    n = 0
    for dart in sorted(SERVICES.rglob("*.dart")):
        if rebuild(dart):
            n += 1
            print(dart.relative_to(CLIENT))
    print(f"rebuilt {n} files")


if __name__ == "__main__":
    main()
