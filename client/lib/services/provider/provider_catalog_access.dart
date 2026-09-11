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
  );
}

bool configProfileCrossMachine(
  ConfigProfilePaths catalog,
  ConfigProfilePaths work,
) => catalog.basePath != work.basePath;
