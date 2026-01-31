; Decorated class: capture the decorated_definition for full range, inner name
(decorated_definition
  definition: (class_definition
    name: (identifier) @class.name)) @class.def

; Decorated function: capture the decorated_definition for full range, inner name
(decorated_definition
  definition: (function_definition
    name: (identifier) @func.name)) @func.def

; Undecorated class (not inside decorated_definition)
(class_definition
  name: (identifier) @class.name) @class.def

; Undecorated function (not inside decorated_definition)
(function_definition
  name: (identifier) @func.name) @func.def
