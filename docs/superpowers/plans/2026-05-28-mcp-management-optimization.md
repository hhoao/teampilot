# MCP Management Optimization Implementation Plan

> **For agentic workers:** Implement tracks A→B→C in order; run `flutter analyze` and MCP tests after each track.

**Goal:** Performance and architecture cleanup for MCP UI/data layer.

**Architecture:** See `docs/superpowers/specs/2026-05-28-mcp-management-optimization-design.md`.

**Tech Stack:** Flutter, flutter_bloc, existing MCP services.

---

### Task 1: Repository cache (B)

- [ ] Add `_cache` to `McpRepository`, invalidate on mutations, `invalidateCache()` public
- [ ] Test: second `loadAll()` does not call filesystem when cache warm

### Task 2: Install + preset helpers (B/C)

- [ ] `mcp_preset_listings.dart` — `mcpBuiltinListings`, `mcpPresetDescription`
- [ ] `mcp_listing_install_service.dart` — resolve + draft with single config load

### Task 3: Discovery cubit (C)

- [ ] `mcp_discovery_cubit.dart` — remote browse state
- [ ] Refactor `mcp_discovery_section.dart` to BlocBuilder
- [ ] Wire cubit in `mcp_management_page.dart`

### Task 4: Installed list performance (A)

- [ ] `mcp_installed_section.dart` — `Expanded` + `ListView.builder`

### Task 5: Verify

- [ ] `flutter analyze` + `flutter test test/services/mcp/`
