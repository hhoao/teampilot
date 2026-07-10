; Minimal JSON highlight captures for tree-sitter-json.
; Extended in later tasks as EditorSyntaxTheme grows more scopes.

(string) @string
(pair key: (string) @property)
(number) @number
[
  (true)
  (false)
] @boolean
(null) @constant.builtin
