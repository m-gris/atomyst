; Query for extracting top-level class and function definitions.
;
; NOTE: This query produces DUPLICATES for decorated definitions because
; both the decorated_definition and inner class/function_definition match.
; Post-processing: for each name, keep only the earliest start_line.
;
; NOTE: tree-sitter uses 0-indexed lines. Convert to 1-indexed for output.
;
; NOTE: Filter to top-level by checking start_column == 0.

; Decorated class - captures full range including decorators
(decorated_definition
  definition: (class_definition
    name: (identifier) @class.name)) @class.def

; Undecorated class
(class_definition
  name: (identifier) @class.name) @class.def

; Decorated function - captures full range including decorators
(decorated_definition
  definition: (function_definition
    name: (identifier) @func.name)) @func.def

; Undecorated function (matches both sync and async)
(function_definition
  name: (identifier) @func.name) @func.def
