import '../cli_capability.dart';

/// Whether this CLI consumes marketplace plugins from CONFIG_DIR.
///
/// Only claude, flashskyai, and cursor consume marketplaces.
/// Replaces the hardcoded `marketplaceConsumerTools` list.
abstract interface class MarketplaceConsumerCapability implements CliCapability {
  bool get consumesMarketplaces;
}
