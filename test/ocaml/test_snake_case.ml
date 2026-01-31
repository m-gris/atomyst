(** Tests for Snake_case module.

    These test cases are ported from the Python test suite to ensure
    parity between implementations.
*)

open Atomyst

(** Test helper: create a test case for snake_case conversion *)
let test_case input expected () =
  Alcotest.(check string) (Printf.sprintf "%s -> %s" input expected)
    expected (Snake_case.to_snake_case input)

(** All conversion test cases from Python test suite *)
let conversion_tests =
  [
    (* Basic PascalCase *)
    ("SimpleClass", "simple_class");

    (* Acronyms at start *)
    ("HTTPServer", "http_server");
    ("XMLParser", "xml_parser");

    (* Acronyms in middle *)
    ("MyHTTPClient", "my_http_client");
    ("AWSLambdaHandler", "aws_lambda_handler");

    (* Single letter *)
    ("A", "a");

    (* Uppercase sequences *)
    ("AB", "ab");
    ("ABCDef", "abc_def");

    (* camelCase with acronyms *)
    ("getHTTPResponse", "get_http_response");

    (* Already snake_case - should be unchanged *)
    ("simple_function", "simple_function");
    ("already_snake_case", "already_snake_case");

    (* All caps *)
    ("ABC", "abc");

    (* Common patterns *)
    ("IOError", "io_error");
    ("getID", "get_id");
    ("HTMLParser", "html_parser");
  ]

let tests =
  List.map
    (fun (input, expected) ->
      Alcotest.test_case input `Quick (test_case input expected))
    conversion_tests

let () =
  Alcotest.run "snake_case"
    [ ("to_snake_case", tests) ]
