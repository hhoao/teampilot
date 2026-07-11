; Minimal TypeScript/TSX highlight captures for tree-sitter-typescript (tsx).
; The tsx grammar also parses .ts/.js/.jsx.

(comment) @comment

(string) @string
(template_string) @string
(regex) @string
(escape_sequence) @string.escape

(number) @number

[
  (true)
  (false)
  (null)
  (undefined)
] @constant.builtin

(type_identifier) @type
(predefined_type) @type.builtin
(property_identifier) @property
(this) @variable.builtin

(function_declaration
  name: (identifier) @function)
(method_definition
  name: (property_identifier) @function)
(call_expression
  function: (identifier) @function)
(call_expression
  function: (member_expression
    property: (property_identifier) @function))

(required_parameter
  (identifier) @variable.parameter)
(optional_parameter
  (identifier) @variable.parameter)

; JSX element / attribute names.
(jsx_opening_element
  name: (identifier) @tag)
(jsx_closing_element
  name: (identifier) @tag)
(jsx_self_closing_element
  name: (identifier) @tag)
(jsx_attribute
  (property_identifier) @attribute)

[
  "abstract"
  "async"
  "await"
  "as"
  "break"
  "case"
  "catch"
  "class"
  "const"
  "continue"
  "declare"
  "default"
  "delete"
  "do"
  "else"
  "enum"
  "export"
  "extends"
  "finally"
  "for"
  "from"
  "function"
  "get"
  "if"
  "implements"
  "import"
  "in"
  "instanceof"
  "interface"
  "keyof"
  "let"
  "namespace"
  "new"
  "of"
  "override"
  "private"
  "protected"
  "public"
  "readonly"
  "return"
  "satisfies"
  "set"
  "static"
  "switch"
  "throw"
  "try"
  "type"
  "typeof"
  "var"
  "void"
  "while"
  "yield"
] @keyword

[
  "=>"
  "=="
  "==="
  "!="
  "!=="
  "&&"
  "||"
  "!"
  "?"
  "="
  "+"
  "-"
  "*"
  "/"
  "%"
  "<"
  ">"
  "<="
  ">="
] @operator

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  ";"
  ":"
  "."
  ","
] @punctuation
