/// Refresh policy for skills/plugins/MCP discovery catalogs.
///
/// Auto-refresh is opt-in (see `AppSettingsRepository.discoveryAutoRefresh`);
/// when enabled, remote catalogs are only checked on page open when the disk
/// cache is older than [kDiscoveryAutoRefreshTtl]. Manual refresh (force)
/// always bypasses the TTL.
const kDiscoveryAutoRefreshTtl = Duration(hours: 24);
