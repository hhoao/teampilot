import '../../../../models/app_provider_config.dart';
import '../opencode_config.dart';
import 'opencode_model_catalog.dart';

/// Which upstream provider a model must be requested from.
///
/// OpenCode Go and OpenCode Zen are **separate upstream providers** in the CLI:
/// different base URLs (`zen/go/v1` vs the built-in Zen endpoint), different
/// `auth.json` entries, and largely disjoint model lists. TeamPilot models them
/// as one catalog row named "OpenCode", so the namespace has to be derived from
/// the model instead of from the row the user clicked.
abstract final class OpencodeModelNamespace {
  OpencodeModelNamespace._();

  static const zen = 'opencode';

  /// Subscription key bound to [provider] (e.g. `opencode-go`), or `''`.
  static String subscriptionKey(AppProviderConfig provider) =>
      opencodeSubscriptionKey(provider);

  /// `models.dev` provider id whose catalog describes [provider]'s paid layer.
  static String catalogKey(AppProviderConfig provider) {
    final subscription = subscriptionKey(provider);
    return subscription.isNotEmpty ? subscription : provider.id.trim();
  }

  /// Namespace a launch should write for [provider] + [modelId].
  ///
  /// Total by construction — there is no "invalid combination" to report:
  /// * no subscription bound ⇒ the provider's own namespace, i.e. Zen for the
  ///   OpenCode row (the free layer) and the row's own id for every other
  ///   provider (a plain OpenAI/Anthropic/custom endpoint);
  /// * model served by the subscription ⇒ the subscription namespace;
  /// * otherwise ⇒ Zen.
  ///
  /// Overlapping ids (models both layers serve) resolve to the subscription:
  /// the user pays for that quota, so using it first is the intended choice.
  static String forModel({
    required AppProviderConfig provider,
    required String modelId,
    Iterable<String>? subscriptionModels,
  }) {
    final subscription = subscriptionKey(provider);
    if (subscription.isEmpty) {
      final id = provider.id.trim();
      return id.isEmpty ? zen : id;
    }

    final model = modelId.trim();
    if (model.isEmpty) return subscription;

    final models = subscriptionModels ?? staticSubscriptionModels(subscription);
    for (final candidate in models) {
      if (candidate.trim() == model) return subscription;
    }
    return zen;
  }

  /// Offline fallback used when the live `models.dev` cache is unavailable.
  static List<String> staticSubscriptionModels(String subscriptionKey) =>
      OpencodeModelCatalog.knownModelsForProvider(subscriptionKey);
}
