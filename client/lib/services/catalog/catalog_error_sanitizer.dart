class CatalogErrorSanitizer {
  const CatalogErrorSanitizer._();

  static String sanitize(String message) {
    var sanitized = message.trim();

    sanitized = sanitized.replaceFirst(
      RegExp(r'response\s+body\s*[:=].*$', caseSensitive: false, dotAll: true),
      '[RESPONSE BODY OMITTED]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'bearer\s+[^\s,;)}\]]+', caseSensitive: false),
      (_) => 'Bearer [REDACTED]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(api[\s_-]*key\s*[:=]\s*)[^\s,;)}\]]+', caseSensitive: false),
      (match) => '${match.group(1)}[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\bsk-[A-Za-z0-9_-]{8,}\b'),
      '[REDACTED]',
    );

    return sanitized;
  }
}
