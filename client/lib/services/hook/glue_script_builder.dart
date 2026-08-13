import '../../models/hook_entry.dart';

/// 生成包住用户命令的粘合脚本（bash / powershell）。
///
/// 契约（所有 CLI 一致）：
/// 1. stdin 透传给用户命令（hook payload 由 CLI 经 stdin 注入）；
/// 2. env 合并（hook.env → 导出）；
/// 3. 用户命令 stdout 非空 → 原样透传；
/// 4. 用户命令 stdout 为空且 policy != none → 输出 writer 提供的决策 JSON；
/// 5. exit code 透传；blockOnDecision → 末尾 `exit 2`。
class GlueScriptBuilder {
  const GlueScriptBuilder();

  String build({
    required HookPolicy policy,
    required String innerCommand,
    String? decisionJson,
    Duration? timeout,
    Map<String, String> env = const {},
    bool blockOnDecision = false,
    required String dialect,
  }) {
    final body = dialect == 'powershell'
        ? _buildPowershell(
            policy: policy,
            innerCommand: innerCommand,
            decisionJson: decisionJson,
            env: env,
            blockOnDecision: blockOnDecision,
          )
        : _buildBash(
            policy: policy,
            innerCommand: innerCommand,
            decisionJson: decisionJson,
            timeout: timeout,
            env: env,
            blockOnDecision: blockOnDecision,
          );
    return dialect == 'powershell'
        ? '# TeamPilot hook glue — do not edit.\n$body'
        : '#!/usr/bin/env bash\n# TeamPilot hook glue — do not edit.\n$body';
  }

  String _buildBash({
    required HookPolicy policy,
    required String innerCommand,
    String? decisionJson,
    Duration? timeout,
    required Map<String, String> env,
    required bool blockOnDecision,
  }) {
    final buffer = StringBuffer('set -u\n');
    for (final entry in env.entries) {
      buffer.writeln("export ${entry.key}=${_shellQuote(entry.value)}");
    }
    if (decisionJson != null) {
      buffer.writeln("DECISION=${_shellQuote(decisionJson)}");
    }
    final inner = _shellQuote(innerCommand);
    final runLine = timeout == null
        ? 'out="\$(eval $inner 2>&1)"'
        : 'out="\$(timeout ${timeout.inSeconds}s eval $inner 2>&1)"';
    buffer
      ..writeln(runLine)
      ..writeln('code=\$?')
      ..writeln('if [ -z "\$out" ] && [ -n "\${DECISION:-}" ]; then')
      ..writeln('  printf \'%s\n\' "\$DECISION"')
      ..writeln('  exit 0')
      ..writeln('fi')
      ..writeln('if [ -n "\$out" ]; then printf \'%s\n\' "\$out"; fi');
    if (blockOnDecision) {
      buffer.writeln('exit 2');
    } else {
      buffer.writeln('exit \$code');
    }
    return buffer.toString();
  }

  String _buildPowershell({
    required HookPolicy policy,
    required String innerCommand,
    String? decisionJson,
    required Map<String, String> env,
    required bool blockOnDecision,
  }) {
    final buffer = StringBuffer("\$ErrorActionPreference = 'Continue'\n");
    for (final entry in env.entries) {
      buffer.writeln("\$env:${entry.key} = '${entry.value.replaceAll("'", "''")}'");
    }
    if (decisionJson != null) {
      buffer.writeln("\$Decision = '${decisionJson.replaceAll("'", "''")}'");
    }
    final inner = innerCommand.replaceAll('"', '\\"');
    buffer
      ..writeln('\$out = cmd /c "$inner" 2>&1 | Out-String')
      ..writeln('\$code = \$LASTEXITCODE')
      ..writeln("if ([string]::IsNullOrWhiteSpace(\$out)) {")
      ..writeln('  if (\$Decision) { Write-Output \$Decision; exit 0 }')
      ..writeln('} else {')
      ..writeln('  Write-Output \$out.TrimEnd()')
      ..writeln('}');
    if (blockOnDecision) {
      buffer.writeln('exit 2');
    } else {
      buffer.writeln('exit \$code');
    }
    return buffer.toString();
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";
}
