; Minimal Rust highlight captures for tree-sitter-rust.

(type_identifier) @type
(primitive_type) @type.builtin
(field_identifier) @property

(call_expression
  function: (identifier) @function)
(call_expression
  function: (field_expression
    field: (field_identifier) @function))
(function_item (identifier) @function)
(function_signature_item (identifier) @function)
(macro_invocation
  macro: (identifier) @function)

(parameter (identifier) @variable.parameter)
(lifetime (identifier) @label)
(self) @variable.builtin

(line_comment) @comment
(block_comment) @comment

(char_literal) @string
(string_literal) @string
(raw_string_literal) @string
(escape_sequence) @string.escape

(boolean_literal) @constant.builtin
(integer_literal) @number
(float_literal) @number

(attribute_item) @attribute
(inner_attribute_item) @attribute

[
  "as"
  "async"
  "await"
  "break"
  "const"
  "continue"
  "default"
  "dyn"
  "else"
  "enum"
  "extern"
  "fn"
  "for"
  "if"
  "impl"
  "in"
  "let"
  "loop"
  "match"
  "mod"
  "move"
  "pub"
  "ref"
  "return"
  "static"
  "struct"
  "trait"
  "type"
  "union"
  "unsafe"
  "use"
  "where"
  "while"
  (crate)
  (mutable_specifier)
  (super)
] @keyword

[
  "*"
  "&"
  "+"
  "-"
  "/"
  "%"
  "="
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "&&"
  "||"
] @operator

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "::"
  ":"
  "."
  ","
  ";"
] @punctuation
