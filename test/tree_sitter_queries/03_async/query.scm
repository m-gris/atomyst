; Decorated async function
(decorated_definition
  definition: (function_definition
    name: (identifier) @async_func.name)) @async_func.def

; Undecorated async function
(function_definition
  name: (identifier) @async_func.name) @async_func.def
