import '../../registry/capabilities/title_attention_capability.dart';

final class NoTitleAttention implements TitleAttentionCapability {
  const NoTitleAttention();
  @override bool get bindTitleAttention => false;
}
