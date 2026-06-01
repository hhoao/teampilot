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

const String codegraphManifestJson = '''
{
  "id": "codegraph",
  "name": "CodeGraph",
  "version": "1.x",
  "homepage": "https://github.com/colbymchenry/codegraph",
  "acquire": {
    "kind": "node-package",
    "package": "@colbymchenry/codegraph",
    "binary": "codegraph",
    "allowNpx": true
  },
  "detect": {
    "executable": "codegraph",
    "versionArgs": ["--version"]
  },
  "effects": [
    {
      "kind": "mcp-server",
      "appliesTo": ["claude", "flashskyai"],
      "name": "codegraph",
      "server": { "command": "codegraph", "args": ["serve", "--mcp"] }
    }
  ]
}
''';

/// All extensions TeamPilot ships with.
List<ExtensionManifest> builtInExtensionManifests() => [
      ExtensionManifest.fromJson(
        jsonDecode(rtkManifestJson) as Map<String, Object?>,
      ),
      ExtensionManifest.fromJson(
        jsonDecode(codegraphManifestJson) as Map<String, Object?>,
      ),
    ];
