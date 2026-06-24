/// Base for all cross-machine artifact transfer failures. The MCP handler
/// catches this and surfaces [toString] as a tool error to the member.
abstract class ArtifactException implements Exception {}

/// No published handle is registered under [name] (or its TTL expired).
class UnknownArtifactException extends ArtifactException {
  UnknownArtifactException(this.name);
  final String name;
  @override
  String toString() =>
      'No artifact named "$name" is published (unknown or expired). '
      'Call list_artifacts to see what is available.';
}

/// A handle with [name] already exists and overwrite was not requested.
class ArtifactNameCollisionException extends ArtifactException {
  ArtifactNameCollisionException(this.name);
  final String name;
  @override
  String toString() =>
      'An artifact named "$name" is already published. Pass overwrite=true to '
      'replace it.';
}

/// The published kind is not supported in v1 (only `file`).
class UnsupportedArtifactKindException extends ArtifactException {
  UnsupportedArtifactKindException(this.kind);
  final String kind;
  @override
  String toString() =>
      'Artifact kind "$kind" is not supported yet. Only single files '
      '(kind=file) can be transferred.';
}

/// The publish source path is missing or is not a regular file.
class ArtifactSourceNotFileException extends ArtifactException {
  ArtifactSourceNotFileException(this.path);
  final String path;
  @override
  String toString() =>
      'Source "$path" is not a regular file (missing, a directory, or a '
      'symlink). Only single files can be published.';
}

/// The artifact exceeds the configured size cap.
class ArtifactTooLargeException extends ArtifactException {
  ArtifactTooLargeException({required this.sizeBytes, required this.maxBytes});
  final int sizeBytes;
  final int maxBytes;
  @override
  String toString() =>
      'Artifact is $sizeBytes bytes, over the $maxBytes byte limit.';
}

/// The fetch destination already exists and overwrite was not requested.
class ArtifactDestinationExistsException extends ArtifactException {
  ArtifactDestinationExistsException(this.destPath);
  final String destPath;
  @override
  String toString() =>
      'Destination "$destPath" already exists. Pass overwrite=true to replace '
      'it.';
}

/// The fetch destination resolves outside the fetching member's inbox area.
class ArtifactDestinationOutsideInboxException extends ArtifactException {
  ArtifactDestinationOutsideInboxException({
    required this.destPath,
    required this.inboxDir,
  });
  final String destPath;
  final String inboxDir;
  @override
  String toString() =>
      'Destination "$destPath" is outside your inbox ("$inboxDir"). A fetch may '
      'only write into your own session inbox.';
}

/// The source bytes could not be read (file vanished between publish and fetch).
class ArtifactSourceUnreadableException extends ArtifactException {
  ArtifactSourceUnreadableException(this.path);
  final String path;
  @override
  String toString() =>
      'Source "$path" could not be read (it may have been moved or deleted '
      'since it was published).';
}
