(** Convert PascalCase/camelCase identifiers to snake_case.

    This module provides name conversion following Python naming conventions.
    Used to convert class names (PascalCase) to file names (snake_case).

    Algorithm (two-pass regex):
    1. Insert underscore before uppercase letters that start a lowercase sequence
       "HTTPServer" -> "HTTP_Server"
    2. Insert underscore between lowercase/digit followed by uppercase
       "HTTP_Server" -> "HTTP_Server" (no change), "getID" -> "get_ID"
    3. Lowercase the result

    Examples:
    - "SimpleClass" -> "simple_class"
    - "HTTPServer" -> "http_server"
    - "XMLParser" -> "xml_parser"
    - "MyHTTPClient" -> "my_http_client"
    - "AWSLambdaHandler" -> "aws_lambda_handler"
    - "getHTTPResponse" -> "get_http_response"
    - "already_snake_case" -> "already_snake_case"
    - "ABC" -> "abc"
    - "IOError" -> "io_error"
    - "getID" -> "get_id"
*)

val to_snake_case : string -> string
(** [to_snake_case name] converts [name] from PascalCase or camelCase to
    snake_case. Already snake_case names are returned unchanged (modulo
    case normalization). *)
