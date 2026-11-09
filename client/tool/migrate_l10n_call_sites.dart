// One-off migration tool: gen_l10n positional l10n calls -> slang named args,
// plus gen_l10n statics -> compat-layer constants.
//
// Usage: cd client && dart run tool/migrate_l10n_call_sites.dart [--dry-run]
//
// Rewrites, across lib/**.dart and test/**.dart (generated files excluded):
//  1. `l10n.key(a, b)` -> `l10n.key(name: a, other: b)` using the exact
//     signatures parsed from lib/l10n/translations_en.g.dart (source of truth).
//  2. `AppLocalizations.localizationsDelegates` -> `appLocalizationsDelegates`
//  3. `AppLocalizations.supportedLocales` -> `appLocalizationsSupportedLocales`
//  4. `AppLocalizations.of(x)` -> `x.l10n` (BuildContextL10n handles both the
//     Localizations-based test path and the TranslationProvider prod path)
//  5. imports of deleted `app_localizations_en.dart`/`_zh.dart` -> shim
//
// Idempotent: already-named argument lists are skipped.

import 'dart:io';

const _skipPaths = <String>{
  'lib/l10n/l10n_extensions.dart',
  'lib/l10n/l10n_compat.dart',
  'lib/l10n/app_localizations.dart',
};

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final debugSkip = args.contains('--debug');
  final root = Directory.current.path;
  final paramSignatures = _parseParamSignatures(
    File('$root/lib/l10n/translations_en.g.dart').readAsStringSync(),
  );
  stdout.writeln('Parsed ${paramSignatures.length} parameterized keys.');

  var filesChanged = 0;
  var callSites = 0;
  var untrusted = 0;
  for (final dir in ['lib', 'test']) {
    for (final entity in Directory('$root/$dir').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.substring(root.length + 1);
      if (rel.endsWith('.g.dart') || _skipPaths.contains(rel)) continue;
      final src = entity.readAsStringSync();
      final (newSrc, calls, bad) = _rewriteFile(src, paramSignatures);
      if (debugSkip && (calls > 0 || bad > 0) && bad > 0) {
        stdout.writeln('SKIP-REPORT $rel');
      }
      if (debugSkip) {
        // Report suspicious keys found in this file (positional calls not rewritten).
        for (final m in RegExp(r'\bl10n\.(\w+)\s*\(').allMatches(src)) {
          final key = m.group(1)!;
          final params = paramSignatures[key];
          if (params == null || params.isEmpty) continue;
          final parsed = _parseArgList(src, m.end - 1);
          if (parsed == null || !parsed.trusted) {
            stdout.writeln('  PARSE-FAIL $rel ${m.start} $key');
            continue;
          }
          final trimmedArgs = parsed.args
              .map((a) => a.trim())
              .where((a) => a.isNotEmpty)
              .toList();
          final firstNamed = trimmedArgs.isNotEmpty &&
              RegExp(r'^\w+\s*:').hasMatch(trimmedArgs.first);
          if (!firstNamed && trimmedArgs.length != params.length) {
            stdout.writeln(
              '  COUNT-MISMATCH $rel ${m.start} $key '
              '${trimmedArgs.length} vs ${params.length} ($params)',
            );
          }
        }
      }
      if (newSrc == src) continue;
      filesChanged++;
      callSites += calls;
      untrusted += bad;
      stdout.writeln(
        '$rel: $calls call site(s)${bad > 0 ? ', $bad UNTRUSTED' : ''}',
      );
      if (!dryRun) entity.writeAsStringSync(newSrc);
    }
  }
  stdout.writeln(
    'Files changed: $filesChanged, call sites rewritten: $callSites, '
    'untrusted: $untrusted${dryRun ? ' (dry run)' : ''}',
  );
}

/// key -> ordered parameter names, parsed from slang's generated signatures:
/// `String name({required int count, required String label}) => ...`
Map<String, List<String>> _parseParamSignatures(String generated) {
  final result = <String, List<String>>{};
  final sigPattern = RegExp(r'^\tString (\w+)\(\{([^}]+)\}\)', multiLine: true);
  final paramPattern = RegExp(r'required \w+ (\w+)');
  for (final match in sigPattern.allMatches(generated)) {
    result[match.group(1)!] = paramPattern
        .allMatches(match.group(2)!)
        .map((m) => m.group(1)!)
        .toList();
  }
  return result;
}

(String, int, int) _rewriteFile(
  String src,
  Map<String, List<String>> signatures,
) {
  var calls = 0;
  var untrusted = 0;
  var out = StringBuffer();
  var pos = 0;
  // No leading \b: receivers may be named `_l10n`; allow whitespace/newline
  // between receiver and member (`l10n\n  .foo(...)`).
  final callPattern = RegExp(r'l10n\s*\.\s*(\w+)\s*\(');

  for (final match in callPattern.allMatches(src)) {
    // Skip matches already consumed by an enclosing rewrite (nested calls).
    if (match.start < pos) continue;
    final key = match.group(1)!;
    final params = signatures[key];
    if (params == null || params.isEmpty) continue;
    final openIdx = match.end - 1;
    final parsed = _parseArgList(src, openIdx);
    if (parsed == null) {
      untrusted++;
      continue;
    }
    final (:end, :args, :trusted) = parsed;
    if (!trusted) {
      untrusted++;
      continue;
    }
    final trimmed = args
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    if (trimmed.isEmpty) continue;
    // Skip already-named lists (idempotency).
    final firstNamed = RegExp(r'^\w+\s*:').hasMatch(trimmed.first);
    if (firstNamed) continue;
    if (trimmed.length != params.length) {
      untrusted++;
      continue;
    }
    out.write(src.substring(pos, match.end));
    for (var i = 0; i < params.length; i++) {
      out.write('${i == 0 ? '' : ', '}${params[i]}: ${trimmed[i]}');
    }
    out.write(')');
    pos = end;
    calls++;
  }
  var result = pos == 0 ? src : '${out.toString()}${src.substring(pos)}';

  // gen_l10n statics -> compat constants.
  result = result
      .replaceAll(
        'AppLocalizations.localizationsDelegates',
        'appLocalizationsDelegates',
      )
      .replaceAll(
        'AppLocalizations.supportedLocales',
        'appLocalizationsSupportedLocales',
      )
      .replaceAll(
        'AppLocalizations.delegate',
        'const AppLocalizationsCompatDelegate()',
      );

  // AppLocalizations.of(x) -> x.l10n (simple identifier receivers only).
  result = result.replaceAllMapped(
    RegExp(r'\bAppLocalizations\.of\((\w+)\)'),
    (m) => '${m.group(1)}.l10n',
  );

  // Imports of deleted generated locale files -> shim.
  result = _fixDeletedImports(result);

  return (result, calls, untrusted);
}

String _fixDeletedImports(String src) {
  final pattern = RegExp(
    r'''(import\s*)(['"])[^'"]*l10n/app_localizations_(en|zh)\.dart(['"];)''',
  );
  return src.replaceAllMapped(
    pattern,
    (m) =>
        "${m.group(1)}${m.group(2)}package:teampilot/l10n/app_localizations.dart${m.group(4)}",
  );
}

typedef _ArgList = ({int end, List<String> args, bool trusted});

/// Quote/comment-aware argument list parser. Returns the index just after the
/// matching `)`, the top-level argument strings, and whether parsing was
/// unambiguous (unterminated string/comment makes it untrusted).
_ArgList? _parseArgList(String src, int openIdx) {
  final args = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var i = openIdx;
  var trusted = true;

  // Frames: code | string(delim) | interp (inside ${})
  final frames = <_Frame>[];
  _Frame frame() => frames.isEmpty ? _codeFrame : frames.last;

  while (i < src.length) {
    final ch = src[i];
    final f = frame();

    // Consume the call's own opening paren without emitting it into the
    // first argument buffer.
    if (i == openIdx) {
      depth++;
      i++;
      continue;
    }

    if (f.kind == _Kind.lineComment) {
      if (ch == '\n') frames.removeLast();
      buf.write(ch);
      i++;
      continue;
    }
    if (f.kind == _Kind.blockComment) {
      if (src.startsWith('*/', i)) {
        frames.removeLast();
        buf.write('*/');
        i += 2;
      } else {
        buf.write(ch);
        i++;
      }
      continue;
    }
    if (f.kind == _Kind.string) {
      if (ch == '\\') {
        buf.write(src.substring(i, i + 2 < src.length ? i + 2 : i + 1));
        i += 2;
        continue;
      }
      if (src.startsWith(r'${', i)) {
        // Record the current global depth so we exit the interpolation when
        // it returns to this level.
        frames.add(_Frame(_Kind.interp, depth: depth));
        buf.write('\${');
        i += 2;
        continue;
      }
      final delim = f.delim;
      if (delim != null && src.startsWith(delim, i)) {
        buf.write(delim);
        i += delim.length;
        frames.removeLast();
        continue;
      }
      buf.write(ch);
      i++;
      continue;
    }
    // code or interp
    if (src.startsWith('//', i)) {
      frames.add(_Frame(_Kind.lineComment));
      buf.write('//');
      i += 2;
      continue;
    }
    if (src.startsWith('/*', i)) {
      frames.add(_Frame(_Kind.blockComment));
      buf.write('/*');
      i += 2;
      continue;
    }
    if (ch == "'" || ch == '"') {
      String delim;
      if (src.startsWith(ch * 3, i)) {
        delim = ch * 3;
      } else {
        delim = ch;
      }
      frames.add(_Frame(_Kind.string, delim: delim));
      buf.write(delim);
      i += delim.length;
      continue;
    }
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
      buf.write(ch);
      i++;
      continue;
    }
    if (ch == ')' || ch == ']' || ch == '}') {
      if (frame().kind == _Kind.interp && ch == '}' && depth == frame().depth) {
        frames.removeLast();
        buf.write(ch);
        i++;
        continue;
      }
      if (depth == 0) {
        // The call's own `(` is consumed as the opener (depth 0 -> 1), so a
        // closer at depth 0 means the source was unbalanced: bail untrusted.
        final arg = buf.toString();
        if (arg.trim().isNotEmpty) args.add(arg);
        return (end: i, args: args, trusted: false);
      }
      depth--;
      if (depth == 0) {
        final arg = buf.toString();
        if (arg.trim().isNotEmpty) args.add(arg);
        return (end: i + 1, args: args, trusted: trusted);
      }
      buf.write(ch);
      i++;
      continue;
    }
    // Top-level argument separator: depth 1 == directly inside the call's
    // paren (the opener itself is consumed at depth 0 -> 1), and not inside
    // a string interpolation.
    if (ch == ',' && depth == 1 && frame().kind == _Kind.code) {
      args.add(buf.toString());
      buf.clear();
      i++;
      continue;
    }
    if (ch == '`') {
      // Unexpected for our sources; mark untrusted.
      trusted = false;
    }
    buf.write(ch);
    i++;
  }
  return null; // unterminated
}

const _codeFrame = _Frame(_Kind.code);

enum _Kind { code, lineComment, blockComment, string, interp }

class _Frame {
  const _Frame(this.kind, {this.delim, this.depth = 0});
  final _Kind kind;
  final String? delim;
  final int depth;
}
