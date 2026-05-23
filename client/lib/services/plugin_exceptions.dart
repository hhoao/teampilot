class PluginException implements Exception {
  PluginException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override String toString() =>
      cause == null ? 'PluginException: $message' : 'PluginException: $message (cause: $cause)';
}

class PluginNotFoundException extends PluginException {
  PluginNotFoundException(String id) : super('Plugin not found: $id');
}

class PluginManifestException extends PluginException {
  PluginManifestException(String path, {Object? cause})
      : super('Failed to parse plugin manifest at $path', cause: cause);
}

class PluginInstallException extends PluginException {
  PluginInstallException(String id, String reason, {Object? cause})
      : super('Plugin install failed [$id]: $reason', cause: cause);
}

class MarketplaceUnreachableException extends PluginException {
  MarketplaceUnreachableException(String marketplace, {Object? cause})
      : super('Marketplace unreachable: $marketplace', cause: cause);
}
