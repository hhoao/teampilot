import '../../registry/capabilities/marketplace_consumer_capability.dart';

final class MarketplaceConsumer implements MarketplaceConsumerCapability {
  const MarketplaceConsumer();
  @override bool get consumesMarketplaces => true;
}
