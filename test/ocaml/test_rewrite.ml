(** Tests for Rewrite module.

    Tests for consumer import rewriting functionality.
*)

open Atomyst

(** Test module_path_of_file conversion *)
let test_module_path_simple () =
  let result = Rewrite.module_path_of_file ~root:"/project" "/project/src/models/domain.py" in
  Alcotest.(check string) "simple path" "src.models.domain" result

let test_module_path_init () =
  let result = Rewrite.module_path_of_file ~root:"/project" "/project/src/models/__init__.py" in
  Alcotest.(check string) "init file" "src.models" result

let test_module_path_relative () =
  let result = Rewrite.module_path_of_file ~root:"/project" "src/foo.py" in
  Alcotest.(check string) "relative path" "src.foo" result

(** Test resolve_relative_import *)
let test_resolve_relative_single_dot () =
  let result = Rewrite.resolve_relative_import ~from_file:"pkg/consumer.py" ~module_ref:".models" in
  Alcotest.(check string) "single dot" "pkg.models" result

let test_resolve_relative_double_dot () =
  let result = Rewrite.resolve_relative_import ~from_file:"pkg/sub/consumer.py" ~module_ref:"..models" in
  Alcotest.(check string) "double dot" "pkg.models" result

let test_resolve_absolute () =
  let result = Rewrite.resolve_relative_import ~from_file:"pkg/consumer.py" ~module_ref:"typing" in
  Alcotest.(check string) "absolute import" "typing" result

(** Test classify_import_name *)
let test_classify_definition () =
  let result = Rewrite.classify_import_name
    ~name:"Query"
    ~defined_names:["Query"; "Mutation"]
    ~reexports:[("Field", "pydantic")]
  in
  Alcotest.(check bool) "is definition"
    true
    (match result with Rewrite.Definition -> true | _ -> false)

let test_classify_reexport () =
  let result = Rewrite.classify_import_name
    ~name:"Field"
    ~defined_names:["Query"]
    ~reexports:[("Field", "pydantic"); ("Base", ".common")]
  in
  match result with
  | Rewrite.Reexport { original_module } ->
    Alcotest.(check string) "reexport module" "pydantic" original_module
  | _ -> Alcotest.fail "expected Reexport"

let test_classify_unknown () =
  let result = Rewrite.classify_import_name
    ~name:"Mystery"
    ~defined_names:["Query"]
    ~reexports:[("Field", "pydantic")]
  in
  Alcotest.(check bool) "is unknown"
    true
    (match result with Rewrite.Unknown -> true | _ -> false)

(* String helper for substring check *)
let string_contains ~sub s =
  let sub_len = String.length sub in
  let s_len = String.length s in
  if sub_len > s_len then false
  else
    let rec check i =
      if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else check (i + 1)
    in
    check 0

let test_generate_simple_rewrite () =
  let import : Rewrite.consumer_import = {
    target_module = ".domain_models";
    names = [
      { name = "Field"; original_name = "Field"; has_alias = false };
      { name = "Query"; original_name = "Query"; has_alias = false };
    ];
    start_row = 0;
    start_col = 0;
    end_row = 0;
    end_col = 50;
    is_relative = true;
    has_star = false;
  } in
  let classifications = [
    ("Field", Rewrite.Reexport { original_module = "pydantic" });
    ("Query", Rewrite.Definition);
  ] in
  let result = Rewrite.generate_replacement_imports ~import ~classifications in
  (* Should have both a definition import and a reexport import *)
  Alcotest.(check bool) "has content"
    true (String.length result > 0);
  Alcotest.(check bool) "contains pydantic"
    true (string_contains ~sub:"pydantic" result);
  Alcotest.(check bool) "contains domain_models"
    true (string_contains ~sub:".domain_models" result)

let test_generate_with_alias () =
  let import : Rewrite.consumer_import = {
    target_module = ".domain_models";
    names = [
      { name = "F"; original_name = "Field"; has_alias = true };
    ];
    start_row = 0;
    start_col = 0;
    end_row = 0;
    end_col = 40;
    is_relative = true;
    has_star = false;
  } in
  let classifications = [
    ("F", Rewrite.Reexport { original_module = "pydantic" });
  ] in
  let result = Rewrite.generate_replacement_imports ~import ~classifications in
  Alcotest.(check bool) "preserves alias"
    true (string_contains ~sub:"Field as F" result)

(** Test suite *)
let () =
  Alcotest.run "rewrite"
    [ ( "module_path_of_file",
        [ Alcotest.test_case "simple" `Quick test_module_path_simple;
          Alcotest.test_case "init" `Quick test_module_path_init;
          Alcotest.test_case "relative" `Quick test_module_path_relative;
        ] );
      ( "resolve_relative_import",
        [ Alcotest.test_case "single_dot" `Quick test_resolve_relative_single_dot;
          Alcotest.test_case "double_dot" `Quick test_resolve_relative_double_dot;
          Alcotest.test_case "absolute" `Quick test_resolve_absolute;
        ] );
      ( "classify_import_name",
        [ Alcotest.test_case "definition" `Quick test_classify_definition;
          Alcotest.test_case "reexport" `Quick test_classify_reexport;
          Alcotest.test_case "unknown" `Quick test_classify_unknown;
        ] );
      ( "generate_replacement_imports",
        [ Alcotest.test_case "simple" `Quick test_generate_simple_rewrite;
          Alcotest.test_case "with_alias" `Quick test_generate_with_alias;
        ] )
    ]
