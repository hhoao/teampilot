; Minimal Python highlight captures for tree-sitter-python.

(identifier) @variable

(function_definition
  name: (identifier) @function)
(call
  function: (identifier) @function)
(call
  function: (attribute
    attribute: (identifier) @function))

(attribute
  attribute: (identifier) @property)
(type (identifier) @type)

(decorator) @attribute

[
  (none)
  (true)
  (false)
] @constant.builtin

[
  (integer)
  (float)
] @number

(comment) @comment
(string) @string
(escape_sequence) @string.escape

[
  "and"
  "in"
  "is"
  "not"
  "or"
  "="
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "+"
  "-"
  "*"
  "/"
  "//"
  "%"
  "**"
] @operator

[
  "as"
  "assert"
  "async"
  "await"
  "break"
  "class"
  "continue"
  "def"
  "del"
  "elif"
  "else"
  "except"
  "finally"
  "for"
  "from"
  "global"
  "if"
  "import"
  "lambda"
  "nonlocal"
  "pass"
  "raise"
  "return"
  "try"
  "while"
  "with"
  "yield"
  "match"
  "case"
] @keyword
