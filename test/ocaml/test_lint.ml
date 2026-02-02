(** Tests for Lint module.

    Pure functions for checking prefix/kind consistency.
    No mocks needed - all functions are pure transformations.
*)

open Atomyst
open Types

(* ============================================================================
   Test helpers
   ============================================================================ *)

let file_result_testable =
  Alcotest.testable
    (fun fmt -> function
      | Lint.Clean -> Format.fprintf fmt "Clean"
      | Lint.Mismatch i ->
        Format.fprintf fmt "Mismatch{file=%s; name=%s; line=%d}"
          i.file_path i.definition_name i.line
      | Lint.NoDefinition -> Format.fprintf fmt "NoDefinition"
      | Lint.ParseError m -> Format.fprintf fmt "ParseError(%s)" m)
    (fun a b -> match a, b with
      | Lint.Clean, Lint.Clean -> true
      | Lint.NoDefinition, Lint.NoDefinition -> true
      | Lint.ParseError _, Lint.ParseError _ -> true
      | Lint.Mismatch a, Lint.Mismatch b ->
        a.definition_name = b.definition_name &&
        a.actual_kind = b.actual_kind
      | _ -> false)

(* ============================================================================
   check_file tests
   ============================================================================ *)

let test_check_file_matching_prefix () =
  let source = "class User:\n    pass\n" in
  let result = Lint.check_file ~dir:"test" ~filename:"class_user.py" ~source in
  Alcotest.(check file_result_testable) "class matches class_" Lint.Clean result

let test_check_file_function_prefix () =
  let source = "def calculate(x):\n    return x * 2\n" in
  let result = Lint.check_file ~dir:"test" ~filename:"def_calculate.py" ~source in
  Alcotest.(check file_result_testable) "def matches def_" Lint.Clean result

let test_check_file_async_prefix () =
  let source = "async def fetch_data():\n    pass\n" in
  let result = Lint.check_file ~dir:"test" ~filename:"async_def_fetch_data.py" ~source in
  Alcotest.(check file_result_testable) "async_def matches async_def_" Lint.Clean result

let test_check_file_mismatch () =
  (* File says class_ but contains a function *)
  let source = "def not_a_class():\n    pass\n" in
  let result = Lint.check_file ~dir:"test" ~filename:"class_user.py" ~source in
  match result with
  | Lint.Mismatch issue ->
    Alcotest.(check string) "definition name" "not_a_class" issue.definition_name;
    Alcotest.(check bool) "expected Class" true (List.mem Class issue.expected_kinds);
    Alcotest.(check (testable pp_definition_kind equal_definition_kind))
      "actual Function" Function issue.actual_kind
  | _ -> Alcotest.fail "Expected Mismatch"

let test_check_file_special_files () =
  let cases = ["_constants.py"; "__init__.py"] in
  List.iter (fun filename ->
    let result = Lint.check_file ~dir:"test" ~filename ~source:"anything" in
    Alcotest.(check file_result_testable) filename Lint.Clean result
  ) cases

let test_check_file_no_prefix () =
  (* Files without prefix are always clean *)
  let source = "def anything():\n    pass\n" in
  let result = Lint.check_file ~dir:"test" ~filename:"user.py" ~source in
  Alcotest.(check file_result_testable) "no prefix = clean" Lint.Clean result

let test_check_file_no_definition () =
  (* Prefixed file with no extractable definition *)
  let source = "# just a comment\nx = 1\n" in
  let result = Lint.check_file ~dir:"test" ~filename:"class_user.py" ~source in
  Alcotest.(check file_result_testable) "no definition" Lint.NoDefinition result

(* ============================================================================
   Test runner
   ============================================================================ *)

let () =
  Alcotest.run "lint"
    [
      ( "check_file",
        [
          Alcotest.test_case "matching class prefix" `Quick test_check_file_matching_prefix;
          Alcotest.test_case "matching def prefix" `Quick test_check_file_function_prefix;
          Alcotest.test_case "matching async_def prefix" `Quick test_check_file_async_prefix;
          Alcotest.test_case "mismatch" `Quick test_check_file_mismatch;
          Alcotest.test_case "special files" `Quick test_check_file_special_files;
          Alcotest.test_case "no prefix" `Quick test_check_file_no_prefix;
          Alcotest.test_case "no definition" `Quick test_check_file_no_definition;
        ] );
    ]
