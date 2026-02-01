; Query for extracting import statements from consumer files.
; Captures the full import statement with position info for rewriting.
;
; NOTE: This query needs to capture:
; 1. The full import_from_statement for position info
; 2. The module being imported from
; 3. All imported names (with aliases if present)
; 4. Star imports (for fail-fast detection)

; from X import Y, Z - simple names
(import_from_statement
  module_name: [
    (dotted_name) @import.module
    (relative_import) @import.module
  ]
  name: (dotted_name (identifier) @import.name)) @import.statement

; from X import Y as Z - aliased imports
(import_from_statement
  module_name: [
    (dotted_name) @import.module
    (relative_import) @import.module
  ]
  name: (aliased_import
    name: (dotted_name (identifier) @import.original)
    alias: (identifier) @import.alias)) @import.statement

; from X import * - star imports (fail fast)
(import_from_statement
  module_name: [
    (dotted_name) @import.module
    (relative_import) @import.module
  ]
  (wildcard_import) @import.star) @import.statement
