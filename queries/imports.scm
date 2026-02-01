; Query for extracting top-level imports.
; Used to detect potential re-exports that won't be available after atomization.

; from X import Y, Z
(import_from_statement
  module_name: (_) @import.module
  name: (dotted_name (identifier) @import.name))

; from X import Y as Z - captures the alias
(import_from_statement
  module_name: (_) @import.module
  name: (aliased_import
    name: (dotted_name (identifier) @import.original)
    alias: (identifier) @import.name))

; import X
(import_statement
  name: (dotted_name) @import.module)

; import X as Y
(import_statement
  name: (aliased_import
    name: (dotted_name) @import.module
    alias: (identifier) @import.name))
