import '../../../models/app_provider_config.dart';
import '../../../repositories/provider_persistence/provider_persistence_strategy.dart';
import 'opencode_config.dart';
import 'opencode_go_layer.dart';
import 'provider/opencode_credential_materializer.dart';
import 'provider/opencode_model_namespace.dart';

/// OpenCode: probe catalog-stored credentials on load. No separate auth store.
final class OpencodeProviderPersistence extends ProviderPersistenceStrategy {
  const OpencodeProviderPersistence();

  @override
  CliTool get cli => CliTool.opencode;

  @override
  Future<List<AppProviderConfig>> reconcileLoaded(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    final migrated = _migrateLegacyGoRows(providers);

    final probed = migrated.map((provider) {
      return provider.withCredentialProbe(
        OpencodeCredentialMaterializer.probe(provider),
      );
    }).toList();

    final changed =
        _rowsDiffer(migrated, probed) || _rowsDiffer(providers, migrated);
    if (changed) {
      await ctx.save(cli, probed);
    }
    return probed;
  }

  static bool _rowsDiffer(
    List<AppProviderConfig> before,
    List<AppProviderConfig> after,
  ) {
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      final previous = before[i];
      final next = after[i];
      if (previous.id != next.id ||
          previous.name != next.name ||
          previous.apiKey != next.apiKey ||
          previous.baseUrl != next.baseUrl ||
          previous.defaultModel != next.defaultModel ||
          previous.config.toString() != next.config.toString() ||
          previous.credentialStatus != next.credentialStatus ||
          previous.credentialUpdatedAt != next.credentialUpdatedAt) {
        return true;
      }
    }
    return false;
  }

  /// Folds the pre-merge `opencode-go` catalog row into the single `opencode`
  /// row, keeping the Go binding.
  ///
  /// Users who saved the old Go preset always had their *whole* row pointed at
  /// `zen/go/v1`, so free Zen models were written as `opencode-go/<model>` and
  /// rejected upstream. One row plus the binding keeps the paid quota while
  /// letting each model resolve to the namespace that actually serves it.
  static List<AppProviderConfig> _migrateLegacyGoRows(
    List<AppProviderConfig> providers,
  ) {
    final goRows = providers
        .where((provider) => OpencodeGoLayer.isNamespace(provider.id))
        .toList();
    if (goRows.isEmpty) return providers;

    AppProviderConfig? zenRow;
    for (final provider in providers) {
      if (provider.id == OpencodeModelNamespace.zen) {
        zenRow = provider;
        break;
      }
    }

    final goRow = goRows.first;
    final base = zenRow ?? goRow;

    final merged = base.copyWith(
      id: OpencodeModelNamespace.zen,
      name: 'OpenCode',
      apiKey: base.apiKey.trim().isNotEmpty ? base.apiKey : goRow.apiKey,
      baseUrl: OpencodeGoLayer.baseUrl,
      defaultModel: base.defaultModel.trim().isNotEmpty
          ? base.defaultModel
          : goRow.defaultModel,
      config: {
        ...goRow.config,
        ...base.config,
        OpencodeProviderConfigKeys.subscription: OpencodeGoLayer.namespace,
        'npm': OpencodeGoLayer.npm,
      },
    );

    final next = <AppProviderConfig>[];
    for (final provider in providers) {
      if (identical(provider, base)) {
        next.add(merged);
      } else if (identical(provider, goRow) ||
          OpencodeGoLayer.isNamespace(provider.id)) {
        // Folded into [merged] above.
        continue;
      } else {
        next.add(provider);
      }
    }
    if (!next.any((provider) => provider.id == OpencodeModelNamespace.zen)) {
      next.insert(0, merged);
    }
    return next;
  }
}
