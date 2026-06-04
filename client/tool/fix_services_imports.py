#!/usr/bin/env python3
"""Fix imports in reorganized client/lib/services using git HEAD as source of truth."""

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
    "team_plugin_linker_service.dart": "plugin",
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

BASENAME_TO_PATH: dict[str, str] = {
    name: f"{subdir}/{name}" for name, subdir in FILE_TO_SUBDIR.items()
}
for p in (SERVICES / "io").glob("*.dart"):
    BASENAME_TO_PATH[p.name] = f"io/{p.name}"

IMPORT_RE = re.compile(r"^import\s+(['\"])([^'\"]+)(['\"]);?\s*$")


def git_head_services_path(path: Path) -> str:
    rel = path.relative_to(SERVICES)
    # Moved files lived flat under services/ in HEAD; io/ was already nested.
    if len(rel.parts) > 1 and rel.parts[0] in set(FILE_TO_SUBDIR.values()):
        return f"client/lib/services/{path.name}"
    return f"client/lib/services/{rel.as_posix()}"


def target_path_for_import(imp: str) -> Path | None:
    if imp.startswith("io/"):
        return SERVICES / imp
    basename = imp.split("/")[-1]
    if basename in BASENAME_TO_PATH:
        return SERVICES / BASENAME_TO_PATH[basename]
    return None


def rel_import(from_file: Path, imp: str) -> str | None:
    target = target_path_for_import(imp)
    if target is None:
        return None
    try:
        return target.relative_to(from_file.parent).as_posix()
    except ValueError:
        prefix = os.path.relpath(target.parent, from_file.parent)
        return f"{prefix}/{target.name}" if prefix != "." else target.name


def rewrite_service_imports_from_git(path: Path) -> bool:
    git_path = git_head_services_path(path)
    try:
        old_text = subprocess.check_output(
            ["git", "show", f"HEAD:{git_path}"],
            cwd=REPO,
            text=True,
        )
    except subprocess.CalledProcessError:
        return False

    # Collect non-package imports from HEAD that point to services
    service_imports: list[str] = []
    for line in old_text.splitlines():
        m = IMPORT_RE.match(line.strip())
        if not m:
            continue
        imp = m.group(2)
        if imp.startswith("dart:") or imp.startswith("package:"):
            continue
        if imp.startswith("../"):
            continue
        if imp.endswith(".dart") and target_path_for_import(imp) is not None:
            new_imp = rel_import(path, imp)
            if new_imp:
                service_imports.append(new_imp)

    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    seen_service: set[str] = set()
    changed = False

    for line in lines:
        m = IMPORT_RE.match(line.strip())
        if not m:
            out.append(line)
            continue
        imp = m.group(2)
        # Drop broken imports
        if imp in ("..", ".") or (
            not imp.endswith(".dart")
            and any(imp.endswith(f"/{d}") or imp == d for d in FILE_TO_SUBDIR.values())
        ):
            changed = True
            continue
        if imp.startswith("io/") and not imp.startswith("../"):
            new_imp = rel_import(path, imp)
            if new_imp and new_imp != imp:
                changed = True
                out.append(f"import '{new_imp}';\n")
                seen_service.add(new_imp)
                continue
        if imp.endswith(".dart") and "/" not in imp and imp in BASENAME_TO_PATH:
            new_imp = rel_import(path, imp)
            if new_imp and new_imp != imp:
                changed = True
                out.append(f"import '{new_imp}';\n")
                seen_service.add(new_imp)
                continue
        # Fix wrong ../remote_file_store from io/
        if imp == "../remote_file_store.dart":
            new_imp = rel_import(path, "remote_file_store.dart")
            if new_imp and new_imp != imp:
                changed = True
                out.append(f"import '{new_imp}';\n")
                seen_service.add(new_imp)
                continue
        if imp.endswith(".dart") and imp.count("/") >= 1:
            basename = imp.split("/")[-1]
            if basename in BASENAME_TO_PATH:
                new_imp = rel_import(path, basename)
                if new_imp and new_imp != imp:
                    changed = True
                    out.append(f"import '{new_imp}';\n")
                    seen_service.add(new_imp)
                    continue
        out.append(line)
        if imp.endswith(".dart") and target_path_for_import(imp.split("/")[-1]):
            seen_service.add(imp)

    # Insert missing imports from git after last import
    missing = [s for s in service_imports if s not in seen_service]
    if missing:
        changed = True
        last_import = 0
        for i, ln in enumerate(out):
            if ln.startswith("import "):
                last_import = i + 1
        for imp in sorted(set(missing)):
            out.insert(last_import, f"import '{imp}';\n")
            last_import += 1

    if changed:
        path.write_text("".join(out), encoding="utf-8")
    return changed


def fix_external_imports(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    changed = False
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        m = IMPORT_RE.match(line.strip())
        if not m:
            out.append(line)
            continue
        q, imp, q2 = m.group(1), m.group(2), m.group(3)
        new_imp: str | None = None
        prefixes = [
            ("package:teampilot/services/", "package:teampilot/services/"),
            ("services/", "services/"),
        ]
        for old_prefix, new_prefix in prefixes:
            if imp.startswith(old_prefix):
                rel = imp[len(old_prefix) :]
                if rel.startswith("io/") or "/" in rel and rel.split("/")[0] in FILE_TO_SUBDIR.values():
                    out.append(line)
                    new_imp = None
                    break
                basename = rel.split("/")[-1]
                if basename in BASENAME_TO_PATH and rel == basename:
                    new_imp = new_prefix + BASENAME_TO_PATH[basename]
                    break
        else:
            out.append(line)
            continue
        if new_imp and new_imp != imp:
            changed = True
            out.append(f"import {q}{new_imp}{q2};\n")
        else:
            out.append(line)
    if changed:
        path.write_text("".join(out), encoding="utf-8")
    return changed


def main() -> None:
    n = 0
    for dart in sorted(SERVICES.rglob("*.dart")):
        if rewrite_service_imports_from_git(dart):
            n += 1
    for dart in (CLIENT / "lib").rglob("*.dart"):
        if dart.is_relative_to(SERVICES):
            continue
        if fix_external_imports(dart):
            n += 1
    for dart in CLIENT.rglob("*.dart"):
        if "test" in dart.parts and fix_external_imports(dart):
            n += 1
    print(f"fixed {n} files")


if __name__ == "__main__":
    main()
