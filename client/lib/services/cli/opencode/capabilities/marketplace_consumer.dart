import '../../registry/capabilities/marketplace_consumer_capability.dart';

final class NoMarketplaceConsumer implements MarketplaceConsumerCapability {
  const NoMarketplaceConsumer();
  @override bool get consumesMarketplaces => false;
}
