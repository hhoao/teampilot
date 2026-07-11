; Minimal Dart highlight captures for tree-sitter-dart.
; Capture names map to EditorSyntaxTheme scopes (with fallback), so predicates
; and nvim-only scopes are intentionally omitted.

(identifier) @variable
(this) @variable.builtin

(comment) @comment
(documentation_comment) @comment

(string_literal) @string
(escape_sequence) @string.escape

[
  (hex_integer_literal)
  (decimal_integer_literal)
  (decimal_floating_point_literal)
] @number

(true) @constant.builtin
(false) @constant.builtin
(null_literal) @constant.builtin

(type_identifier) @type
(class_definition
  name: (identifier) @type)
(enum_declaration
  name: (identifier) @type)
(function_signature
  name: (identifier) @function)

(formal_parameter
  name: (identifier) @variable.parameter)

(annotation
  "@" @attribute
  name: (identifier) @attribute)

[
  (assert_builtin)
  (break_builtin)
  (const_builtin)
  (rethrow_builtin)
  (void_type)
  "abstract"
  "as"
  "async"
  "await"
  "case"
  "catch"
  "class"
  "continue"
  "default"
  "do"
  "else"
  "enum"
  "export"
  "extends"
  "extension"
  "external"
  "factory"
  "final"
  "finally"
  "for"
  "get"
  "hide"
  "if"
  "implements"
  "import"
  "in"
  "interface"
  "is"
  "late"
  "library"
  "mixin"
  "new"
  "on"
  "part"
  "required"
  "return"
  "sealed"
  "set"
  "show"
  "static"
  "super"
  "switch"
  "throw"
  "try"
  "typedef"
  "var"
  "when"
  "while"
  "with"
  "yield"
] @keyword

[
  "=>"
  "=="
  "?"
  ":"
  "&&"
  "||"
  "%"
  "<"
  ">"
  "="
  ">="
  "<="
  (increment_operator)
  (is_operator)
  (prefix_operator)
  (equality_operator)
  (additive_operator)
] @operator

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  ";"
  "."
  ","
] @punctuation
