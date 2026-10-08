class PluginException implements Exception {
  PluginException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => cause == null
      ? 'PluginException: $message'
      : 'PluginException: $message (cause: $cause)';
}

class PluginNotFoundException extends PluginException {
  PluginNotFoundException(String id) : super('Plugin not found: $id');
}

class PluginManifestException extends PluginException {
  PluginManifestException(String path, {super.cause})
    : super('Failed to parse plugin manifest at $path');
}

class PluginInstallException extends PluginException {
  PluginInstallException(String id, String reason, {super.cause})
    : super('Plugin install failed [$id]: $reason');
}

class MarketplaceUnreachableException extends PluginException {
  MarketplaceUnreachableException(String marketplace, {super.cause})
    : super('Marketplace unreachable: $marketplace');
}
