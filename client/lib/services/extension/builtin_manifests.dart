import 'dart:convert';

import '../../models/extension_manifest.dart';

/// rtk manifest, embedded as JSON to exercise the parser and keep the
/// "an extension is data" contract. Externalized to a bundled asset in a
/// later phase.
const String rtkManifestJson = '''
{
  "id": "rtk",
  "name": "RTK (Rust Token Killer)",
  "version": "0.x",
  "homepage": "https://github.com/rtk-ai/rtk",
  "acquire": {
    "kind": "cargo",
    "package": "rtk",
    "binary": "rtk",
    "alternatives": ["brew:rtk"]
  },
  "detect": {
    "executable": "rtk",
    "versionArgs": ["--version"],
    "minVersion": "0.23.0",
    "requires": ["jq"]
  },
  "effects": [
    {
      "kind": "settings-hook",
      "appliesTo": ["claude", "flashskyai"],
      "event": "PreToolUse",
      "matcher": "Bash",
      "scriptAsset": "rtk-rewrite",
      "marker": "rtk-rewrite"
    }
  ]
}
''';

/// All extensions TeamPilot ships with. Phase 1: rtk only.
List<ExtensionManifest> builtInExtensionManifests() => [
      ExtensionManifest.fromJson(
        jsonDecode(rtkManifestJson) as Map<String, Object?>,
      ),
    ];
