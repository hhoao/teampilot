; Minimal Bash highlight captures for tree-sitter-bash.

[
  (string)
  (raw_string)
  (heredoc_body)
  (heredoc_start)
] @string

(command_name) @function
(function_definition
  name: (word) @function)

(variable_name) @property

(comment) @comment

(file_descriptor) @number

[
  "case"
  "do"
  "done"
  "elif"
  "else"
  "esac"
  "export"
  "fi"
  "for"
  "function"
  "if"
  "in"
  "select"
  "then"
  "unset"
  "until"
  "while"
] @keyword

[
  "$"
  "&&"
  "||"
  ">"
  ">>"
  "<"
  "|"
  "="
] @operator
