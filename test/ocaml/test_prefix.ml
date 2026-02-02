(** Tests for Prefix module.

    Pure functions for filename prefix generation and parsing.
    No mocks needed - all functions are pure transformations.
*)

open Atomyst
open Types

(* ============================================================================
   kind_to_prefix tests
   ============================================================================ *)

let test_kind_to_prefix () =
  let cases =
    [
      (Class, "class");
      (Function, "def");
      (AsyncFunction, "async_def");
      (Variable, "var");
      (TypeAlias, "type");
    ]
  in
  List.iter
    (fun (kind, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "%s -> %s" (show_definition_kind kind) expected)
        expected (Prefix.kind_to_prefix kind))
    cases

(* ============================================================================
   generate_filename tests
   ============================================================================ *)

let make_defn name kind =
  { name; kind; start_line = 1; end_line = 1 }

let test_generate_filename_no_prefix () =
  let cases =
    [
      (make_defn "User" Class, "user.py");
      (make_defn "calculate" Function, "calculate.py");
      (make_defn "fetchData" AsyncFunction, "fetch_data.py");
      (make_defn "MAX_SIZE" Variable, "max_size.py");
      (make_defn "UserId" TypeAlias, "user_id.py");
    ]
  in
  List.iter
    (fun (defn, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "%s -> %s" defn.name expected)
        expected (Prefix.generate_filename ~prefix_kind:false defn))
    cases

let test_generate_filename_with_prefix () =
  let cases =
    [
      (make_defn "User" Class, "class_user.py");
      (make_defn "calculate" Function, "def_calculate.py");
      (make_defn "fetchData" AsyncFunction, "async_def_fetch_data.py");
      (make_defn "MAX_SIZE" Variable, "var_max_size.py");
      (make_defn "UserId" TypeAlias, "type_user_id.py");
    ]
  in
  List.iter
    (fun (defn, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "%s -> %s" defn.name expected)
        expected (Prefix.generate_filename ~prefix_kind:true defn))
    cases

(* ============================================================================
   parse_filename tests
   ============================================================================ *)

let parsed_filename_testable =
  Alcotest.testable
    (fun fmt pf ->
      Format.fprintf fmt "{prefix=%s; base_name=%s}" pf.Prefix.prefix
        pf.Prefix.base_name)
    (fun a b -> a.Prefix.prefix = b.Prefix.prefix && a.base_name = b.base_name)

let test_parse_filename_with_prefix () =
  let cases =
    [
      ("class_user.py", Some { Prefix.prefix = "class"; base_name = "user" });
      ("def_calculate.py", Some { Prefix.prefix = "def"; base_name = "calculate" });
      ("async_def_fetch_data.py", Some { Prefix.prefix = "async_def"; base_name = "fetch_data" });
      ("var_max_size.py", Some { Prefix.prefix = "var"; base_name = "max_size" });
      ("type_user_id.py", Some { Prefix.prefix = "type"; base_name = "user_id" });
    ]
  in
  List.iter
    (fun (filename, expected) ->
      Alcotest.(check (option parsed_filename_testable))
        filename expected (Prefix.parse_filename filename))
    cases

let test_parse_filename_no_prefix () =
  let cases =
    [
      ("user.py", None);
      ("calculate.py", None);
      ("_constants.py", None);
      ("__init__.py", None);
      ("not_a_prefix_really.py", None);  (* "not" is not a valid prefix *)
    ]
  in
  List.iter
    (fun (filename, expected) ->
      Alcotest.(check (option parsed_filename_testable))
        filename expected (Prefix.parse_filename filename))
    cases

let test_parse_filename_edge_cases () =
  let cases =
    [
      ("class_.py", None);              (* empty base_name *)
      ("def.py", None);                 (* just prefix, no underscore *)
      ("class_a.py", Some { Prefix.prefix = "class"; base_name = "a" });  (* single char *)
      ("async_def_a_b_c.py", Some { Prefix.prefix = "async_def"; base_name = "a_b_c" });
    ]
  in
  List.iter
    (fun (filename, expected) ->
      Alcotest.(check (option parsed_filename_testable))
        filename expected (Prefix.parse_filename filename))
    cases

(* ============================================================================
   prefix_to_kinds tests
   ============================================================================ *)

let definition_kind_list_testable =
  Alcotest.(list (testable pp_definition_kind equal_definition_kind))

let test_prefix_to_kinds () =
  let cases =
    [
      ("class", [Class]);
      ("def", [Function]);
      ("async_def", [AsyncFunction]);
      ("var", [Variable]);
      ("type", [TypeAlias]);
      ("unknown", []);
      ("", []);
    ]
  in
  List.iter
    (fun (prefix, expected) ->
      Alcotest.(check definition_kind_list_testable)
        prefix expected (Prefix.prefix_to_kinds prefix))
    cases

(* ============================================================================
   is_special_file tests
   ============================================================================ *)

let test_is_special_file () =
  let cases =
    [
      ("_constants.py", true);
      ("__init__.py", true);
      ("user.py", false);
      ("class_user.py", false);
      ("constants.py", false);  (* no leading underscore *)
    ]
  in
  List.iter
    (fun (filename, expected) ->
      Alcotest.(check bool) filename expected (Prefix.is_special_file filename))
    cases

(* ============================================================================
   Test runner
   ============================================================================ *)

let () =
  Alcotest.run "prefix"
    [
      ( "kind_to_prefix",
        [ Alcotest.test_case "all kinds" `Quick test_kind_to_prefix ] );
      ( "generate_filename",
        [
          Alcotest.test_case "no prefix" `Quick test_generate_filename_no_prefix;
          Alcotest.test_case "with prefix" `Quick test_generate_filename_with_prefix;
        ] );
      ( "parse_filename",
        [
          Alcotest.test_case "with prefix" `Quick test_parse_filename_with_prefix;
          Alcotest.test_case "no prefix" `Quick test_parse_filename_no_prefix;
          Alcotest.test_case "edge cases" `Quick test_parse_filename_edge_cases;
        ] );
      ( "prefix_to_kinds",
        [ Alcotest.test_case "all mappings" `Quick test_prefix_to_kinds ] );
      ( "is_special_file",
        [ Alcotest.test_case "special vs normal" `Quick test_is_special_file ] );
    ]
