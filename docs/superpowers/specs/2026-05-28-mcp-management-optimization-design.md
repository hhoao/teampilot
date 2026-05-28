# MCP Management Optimization Design

**Date:** 2026-05-28  
**Status:** Approved for implementation

## Goal

Improve MCP management performance, reduce redundant I/O and orchestration code, and lift discovery state into a Cubit without changing user-visible behavior.

## Scope

| Track | Change |
|-------|--------|
| A | Installed list uses `ListView.builder` inside card (bounded height) |
| B | `McpRepository` in-memory catalog cache; single registry load for Smithery install |
| C | `McpDiscoveryCubit` + `McpListingInstallService`; thinner pages |
| D | This spec + implementation plan in `docs/superpowers/` |

## Architecture

- **Repository cache:** After first `loadAll()`, serve from memory until `upsert`/`delete`/`invalidateCache()`.
- **Install service:** `McpListingInstallService` resolves Smithery detail + applies catalog Bearer using one `McpRegistryConfigService.load()`.
- **Discovery cubit:** Owns source, query, remote items, pagination, registry config, loading/error. Builtin presets filtered in UI from `mcpBuiltinListings(l10n)`.
- **UI:** `McpManagementPage` creates/disposes `McpDiscoveryCubit`; provides via `BlocProvider.value` when section is discovery.

## Non-goals

- Disk format change for `mcp_servers.json`
- Image caching library for discovery icons
- Full widget/integration tests (follow-up)

## Testing

- Unit test: repository cache returns same list without second file read
- `flutter analyze` + existing MCP service tests
