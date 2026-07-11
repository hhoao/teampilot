; Minimal XML highlight captures for tree-sitter-xml (also used for HTML this
; phase). Node types follow the grammar's XML document rules.

(Comment) @comment

(STag (Name) @tag)
(ETag (Name) @tag)
(EmptyElemTag (Name) @tag)

(Attribute (Name) @property)
(Attribute (AttValue) @string)

(EntityRef) @constant
(CharRef) @constant

(doctypedecl "DOCTYPE" @keyword)
(doctypedecl (Name) @type)

(PI (PITarget) @keyword)

[
  "<?" "?>"
  "<!" "]]>"
  "<" ">"
  "</" "/>"
] @punctuation

[ "=" ] @operator
