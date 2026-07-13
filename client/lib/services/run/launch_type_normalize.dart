import 'shell_script_launch_schema.dart';

/// Whether [type] is the built-in shell script launch type.
bool isBuiltInShellType(String type) =>
    type == ShellScriptLaunchSchema.typeName;
