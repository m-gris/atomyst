(** Tests for Extract module.

    These tests verify that extract_definitions produces the same results
    as the Python implementation when run on the same fixtures.
*)

open Atomyst
open Types

(** Test helper: read a fixture file.
    Path is relative to project root (ensured by dune chdir). *)
let read_fixture path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

(** Test helper: create definition for comparison *)
let def name kind start_line end_line =
  { name; kind; start_line; end_line }

(** Helper to compare definitions *)
let definition_testable =
  Alcotest.testable pp_definition equal_definition

let definitions_testable =
  Alcotest.(list definition_testable)

(* ============================================================
   Test: 01_simple_class
   Expected: Person lines 6-14 (with @dataclass decorator on line 6)
   ============================================================ *)
let test_01_simple_class () =
  let source = read_fixture "test/fixtures/01_simple_class/input.py" in
  let defs = Extract.extract_definitions source in
  Alcotest.(check definitions_testable) "single class"
    [ def "Person" Class 6 14 ]
    defs

(* ============================================================
   Test: 02_multiple_classes
   Expected from Python: Point 7-12, Rectangle 15-28, Circle 31-37
   ============================================================ *)
let test_02_multiple_classes () =
  let source = read_fixture "test/fixtures/02_multiple_classes/input.py" in
  let defs = Extract.extract_definitions source in
  Alcotest.(check definitions_testable) "multiple classes"
    [ def "Point" Class 7 12;
      def "Rectangle" Class 15 28;
      def "Circle" Class 31 37 ]
    defs

(* ============================================================
   Test: 03_decorators
   Expected from Python: log_calls 10-18, Priority 21-30, expensive_computation 33-37
   ============================================================ *)
let test_03_decorators () =
  let source = read_fixture "test/fixtures/03_decorators/input.py" in
  let defs = Extract.extract_definitions source in
  Alcotest.(check definitions_testable) "decorated definitions"
    [ def "log_calls" Function 10 18;
      def "Priority" Class 21 30;
      def "expensive_computation" Function 33 37 ]
    defs

(* ============================================================
   Test: 06_async_functions
   Expected from Python: fetch_data 7-10, process_items 13-15, AsyncClient 18-27
   Note: OCaml treats async functions as Function, not AsyncFunction
   ============================================================ *)
let test_06_async_functions () =
  let source = read_fixture "test/fixtures/06_async_functions/input.py" in
  let defs = Extract.extract_definitions source in
  Alcotest.(check definitions_testable) "async functions"
    [ def "fetch_data" Function 7 10;
      def "process_items" Function 13 15;
      def "AsyncClient" Class 18 27 ]
    defs

(* ============================================================
   Test suite
   ============================================================ *)
let () =
  Alcotest.run "extract"
    [ ( "extract_definitions",
        [ Alcotest.test_case "01_simple_class" `Quick test_01_simple_class;
          Alcotest.test_case "02_multiple_classes" `Quick test_02_multiple_classes;
          Alcotest.test_case "03_decorators" `Quick test_03_decorators;
          Alcotest.test_case "06_async_functions" `Quick test_06_async_functions
        ] )
    ]
