import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const builder = GlueScriptBuilder();

  test('bash glue injects decision JSON on empty output', () {
    final script = builder.build(
      policy: HookPolicy.deny,
      innerCommand: 'echo run',
      decisionJson: '{"permissionDecision":"deny"}',
      dialect: 'bash',
    );
    expect(script, contains('#!/usr/bin/env bash'));
    expect(script, contains("DECISION='{\"permissionDecision\":\"deny\"}'"));
    expect(script, contains("eval 'echo run'"));
    expect(script, contains('exit 0'));
    expect(script, contains('exit \$code'));
  });

  test('bash glue passes through user stdout verbatim', () {
    final script = builder.build(
      policy: HookPolicy.none,
      innerCommand: 'echo hi',
      dialect: 'bash',
    );
    expect(script, contains("printf '%s\\n' \"\$out\""));
    expect(script, isNot(contains('DECISION=')));
  });

  test('bash glue applies timeout and env and blockOnDecision exit 2', () {
    final script = builder.build(
      policy: HookPolicy.none,
      innerCommand: 'echo hi',
      timeout: const Duration(seconds: 9),
      env: const {'FOO': 'bar'},
      blockOnDecision: true,
      dialect: 'bash',
    );
    expect(script, contains("export FOO='bar'"));
    expect(script, contains('timeout 9s bash -c'));
    expect(script, contains('exit 2'));
    expect(script, isNot(contains('exit \$code')));
  });

  test('powershell glue injects decision and forwards via cmd /c', () {
    final script = builder.build(
      policy: HookPolicy.allow,
      innerCommand: 'echo run',
      decisionJson: '{"permissionDecision":"allow"}',
      dialect: 'powershell',
    );
    expect(script, contains('cmd /c'));
    expect(script, contains('\$Decision'));
    expect(script, contains('\$LASTEXITCODE'));
    expect(script, contains('# TeamPilot hook glue'));
  });

  test('single quotes in inner command are escaped for bash', () {
    final script = builder.build(
      policy: HookPolicy.none,
      innerCommand: "echo 'it''s'",
      dialect: 'bash',
    );
    expect(script, contains(r"'echo '\''it"));
  });
}
