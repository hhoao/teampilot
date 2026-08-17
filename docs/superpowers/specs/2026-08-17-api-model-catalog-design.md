# API Model Catalogs for Codex and Claude

## Goal

Add reliable model discovery for Codex/OpenAI and Claude/Anthropic providers that use an API key or custom API endpoint, while preserving static model choices for ChatGPT/Claude.ai OAuth and offline use.

## Scope

- Refresh model IDs from OpenAI-compatible and Anthropic-compatible `/models` endpoints.
- Pass the complete `AppProviderConfig` into refreshable model capabilities so endpoint and credential settings are available.
- Cache only model IDs and timestamps per provider; never persist API keys in the model cache.
- Use memory cache, disk cache, and then static catalogs as the fallback chain.
- Keep OAuth/subscription providers on static catalogs and do not inspect private product endpoints.
- Add current official coding/agent model IDs to the Codex and Claude static catalogs.
- Add unit tests for request construction, response parsing, cache behavior, fallback behavior, and capability integration.

## Non-goals

- No reverse engineering of Codex or Claude Code private OAuth APIs.
- No API key probing or model-by-model completion requests.
- No provider credential storage changes.
- No new UI refresh control; the existing provider model picker refresh lifecycle is reused.

## Architecture

`ProviderModelPickerField` passes its `AppProviderConfig` to `refreshModelCatalog`. Codex and Claude capabilities implement `RefreshableProviderModelCapability` and delegate to injected model services. Each service owns endpoint resolution, authentication headers, response parsing, per-provider in-memory state, disk cache, TTL handling, and update notifications.

The services fetch only when the provider has a non-empty API key. An empty `baseUrl` selects the official API endpoint; a custom `baseUrl` is normalized according to the CLI's provider protocol. A successful live response replaces the provider's cached model IDs. A failed request leaves a valid disk or memory cache intact and exposes the static catalog through the capability source when no live IDs are available.

The cache format is:

```json
{
  "fetchedAtMs": 0,
  "modelIds": ["model-a", "model-b"]
}
```

Cache paths are under the application data root:

- `cache/codex_models/<providerId>.json`
- `cache/claude_models/<providerId>.json`

Provider IDs are path-safe identifiers already used by the provider catalog. The service must still use the filesystem path context for joining paths.

## Model catalogs

Static catalogs are intentionally limited to models useful for coding/agent launches rather than every audio, image, embedding, or moderation model in the API catalog.

- Codex/OpenAI includes the current GPT-5.6 family and GPT-5.3-Codex family, plus existing Codex-compatible IDs retained for existing configurations.
- Claude includes the current generally released Fable, Opus, Sonnet, and Haiku IDs from the official model overview, plus existing Claude Code aliases and retained IDs.
- Invitation-only or preview-only models are not added to the default fallback unless already explicitly configured by the user; provider-declared and current model values are always merged by `CatalogModelCapability`.

## Error handling

- Network, timeout, invalid JSON, non-success status, missing API key, and empty model responses are treated as refresh misses.
- Refresh misses do not throw from the picker lifecycle.
- Existing disk cache is used when it is present, valid, and the live request fails.
- Static fallback remains available for official providers even before the first successful refresh.
- API keys are sent only in request headers and never included in diagnostics, cache entries, or thrown user-facing errors.

## Testing

- Pure tests cover endpoint normalization, headers, response parsing, deduplication, and filtering.
- Service tests use `MockClient` and `InMemoryFilesystem` to verify successful refresh, cache reads/writes, TTL, and failed-refresh fallback without network access.
- Capability tests verify API-backed live IDs take precedence, OAuth providers use static IDs, and current static IDs are present.
- Existing non-integration Flutter test and analyze commands remain the final verification gate.

