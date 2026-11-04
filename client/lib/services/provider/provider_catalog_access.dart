import '../../repositories/app_provider_repository.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../storage/home_storage.dart';

AppProviderRepository providerCatalogRepository(
  ConfigProfilePaths catalog, {
  required HomeStorage storage,
}) {
  return AppProviderRepository(
    basePath: catalog.basePath,
    fs: catalog.fs,
    storage: storage,
    // Explicit: launch-time callers must resolve `vault:` links exactly like
    // the provider cubit does.
    linkedCredentialLookup:
        AppProviderRepository.defaultLinkedCredentialLookup,
  );
}

bool configProfileCrossMachine(
  ConfigProfilePaths catalog,
  ConfigProfilePaths work,
) => catalog.basePath != work.basePath;
