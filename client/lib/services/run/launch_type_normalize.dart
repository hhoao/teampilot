import 'shell_script_launch_schema.dart';

/// Maps legacy `process` wire type to built-in [ShellScriptLaunchSchema.typeName].
String normalizeLaunchType(String type) =>
    type == ShellScriptLaunchSchema.processAlias
        ? ShellScriptLaunchSchema.typeName
        : type;

/// Whether [type] is the built-in shell script launch type (including `process` alias).
bool isBuiltInShellType(String type) =>
    normalizeLaunchType(type) == ShellScriptLaunchSchema.typeName;
