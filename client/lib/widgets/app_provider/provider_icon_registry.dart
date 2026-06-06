import 'package:flutter/material.dart';

import 'provider_icon_catalog.g.dart';

/// CodePilot [iconKey] and other aliases → cc-switch icon ids.
const Map<String, String> providerIconAliases = {
  'moonshot': 'kimi',
  'volcengine': 'huoshan',
  'xiaomi-mimo': 'xiaomimimo',
  'bedrock': 'aws',
  'vertex': 'googlecloud',
  'wenxin': 'wenxin',
  'yiyan': 'wenxin',
  'doubao-ark': 'huoshan',
  'byteplus-ark': 'byteplus',
};

/// Fixed dark tile behind all provider / CLI brand marks.
const Color kProviderIconTileBackground = Color.fromARGB(255, 240, 240, 240);

const Color kProviderIconTileBackgroundLight = Color.fromARGB(
  255,
  237,
  237,
  237,
);

/// Text on dark tiles when no SVG asset is available.
const Color kProviderIconFallbackForeground = Color.fromARGB(255, 97, 97, 97);

const Color kProviderIconFallbackForegroundLight = Color.fromARGB(
  255,
  130,
  130,
  130,
);

/// Normalizes [raw] (preset `icon`, CodePilot `iconKey`, etc.) to a catalog key.
String normalizeProviderIconKey(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final key = trimmed.toLowerCase();
  return providerIconAliases[key] ?? key;
}

/// Asset path under `assets/providers/`, or null when no bundled icon exists.
String? providerIconAssetPath(String raw) {
  final key = normalizeProviderIconKey(raw);
  if (key.isEmpty) return null;
  return providerIconAssetPaths[key];
}

bool providerIconExists(String raw) => providerIconAssetPath(raw) != null;

Color resolveProviderIconTileBackground(ColorScheme scheme, bool isDark) =>
    isDark ? kProviderIconTileBackground : kProviderIconTileBackgroundLight;

Color resolveProviderIconForeground(ColorScheme scheme, bool isDark) => isDark
    ? kProviderIconFallbackForeground
    : kProviderIconFallbackForegroundLight;

Color resolveProviderIconBorderColor(ColorScheme scheme, bool isDark) => isDark
    ? Colors.white.withValues(alpha: 0.12)
    : Colors.black.withValues(alpha: 0.12);
