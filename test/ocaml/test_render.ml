(** Tests for Render module. *)

open Atomyst
open Types

(** Test plan_text output format *)
let test_plan_text () =
  let plan = {
    source_name = "test.py";
    definitions = [
      { name = "Foo"; kind = Class; start_line = 1; end_line = 5 };
      { name = "bar"; kind = Function; start_line = 7; end_line = 10 };
    ];
    output_files = [
      { relative_path = "foo.py"; content = "class Foo:\n    pass\n" };
      { relative_path = "bar.py"; content = "def bar():\n    pass\n" };
      { relative_path = "__init__.py"; content = "from .foo import Foo\n" };
    ];
  } in
  let output = Render.plan_text plan in

  Alcotest.(check bool) "contains definitions count"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "2 definitions") output 0 in true);
  Alcotest.(check bool) "contains Foo"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "Foo") output 0 in true);
  Alcotest.(check bool) "contains bar"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "bar") output 0 in true);
  Alcotest.(check bool) "contains file count"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "3 files") output 0 in true)

(** Test plan_json output is valid JSON *)
let test_plan_json () =
  let plan = {
    source_name = "test.py";
    definitions = [
      { name = "Foo"; kind = Class; start_line = 1; end_line = 5 };
    ];
    output_files = [
      { relative_path = "foo.py"; content = "class Foo:\n    pass\n" };
    ];
  } in
  let json_str = Render.plan_json plan in
  (* Should parse without error *)
  let json = Yojson.Basic.from_string json_str in
  (* Check structure *)
  let source = Yojson.Basic.Util.(json |> member "source" |> to_string) in
  Alcotest.(check string) "source field" "test.py" source

(** Test extraction_text dry run format *)
let test_extraction_text_dry_run () =
  let result = {
    extracted = { relative_path = "foo.py"; content = "class Foo:\n    pass\n" };
    remainder = "# rest of file\n";
  } in
  let output = Render.extraction_text result ~name:"Foo" ~dry_run:true in

  Alcotest.(check bool) "contains DRY RUN"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "DRY RUN") output 0 in true);
  Alcotest.(check bool) "contains name"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "Foo") output 0 in true)

(** Test extraction_text non-dry-run format *)
let test_extraction_text_written () =
  let result = {
    extracted = { relative_path = "foo.py"; content = "class Foo:\n    pass\n" };
    remainder = "";
  } in
  let output = Render.extraction_text result ~name:"Foo" ~dry_run:false in

  Alcotest.(check bool) "contains Extracted"
    true (String.length output > 0 &&
          let _ = Str.search_forward (Str.regexp "Extracted") output 0 in true);
  Alcotest.(check bool) "no DRY RUN"
    true (try let _ = Str.search_forward (Str.regexp "DRY RUN") output 0 in false
          with Not_found -> true)

(** Test extraction_json format *)
let test_extraction_json () =
  let result = {
    extracted = { relative_path = "foo.py"; content = "class Foo:\n    pass\n" };
    remainder = "# rest\n";
  } in
  let json_str = Render.extraction_json result ~name:"Foo" in
  let json = Yojson.Basic.from_string json_str in
  let name = Yojson.Basic.Util.(json |> member "name" |> to_string) in
  Alcotest.(check string) "name field" "Foo" name

(** Test error formatting *)
let test_error () =
  let output = Render.error "something went wrong" in
  Alcotest.(check string) "error format"
    "Error: something went wrong" output

(** Test manifest YAML format *)
let test_manifest_yaml () =
  let definitions = [
    { name = "Foo"; kind = Class; start_line = 1; end_line = 5 };
    { name = "bar"; kind = Function; start_line = 7; end_line = 10 };
  ] in
  let (content, filename) = Render.manifest ~format:"yaml" ~source_name:"test.py" ~prefix_kind:false ~definitions in
  Alcotest.(check string) "filename" "MANIFEST.yaml" filename;
  Alcotest.(check bool) "contains source"
    true (let _ = Str.search_forward (Str.regexp "source: test.py") content 0 in true);
  Alcotest.(check bool) "contains Foo"
    true (let _ = Str.search_forward (Str.regexp "name: Foo") content 0 in true);
  Alcotest.(check bool) "contains foo.py"
    true (let _ = Str.search_forward (Str.regexp "file: foo.py") content 0 in true)

(** Test manifest JSON format *)
let test_manifest_json () =
  let definitions = [
    { name = "Foo"; kind = Class; start_line = 1; end_line = 5 };
  ] in
  let (content, filename) = Render.manifest ~format:"json" ~source_name:"test.py" ~prefix_kind:false ~definitions in
  Alcotest.(check string) "filename" "MANIFEST.json" filename;
  let json = Yojson.Basic.from_string content in
  let source = Yojson.Basic.Util.(json |> member "source" |> to_string) in
  Alcotest.(check string) "source field" "test.py" source

(** Test manifest MD format *)
let test_manifest_md () =
  let definitions = [
    { name = "Foo"; kind = Class; start_line = 1; end_line = 5 };
  ] in
  let (content, filename) = Render.manifest ~format:"md" ~source_name:"test.py" ~prefix_kind:false ~definitions in
  Alcotest.(check string) "filename" "MANIFEST.md" filename;
  Alcotest.(check bool) "contains header"
    true (let _ = Str.search_forward (Str.regexp "# Atomyst Manifest") content 0 in true);
  Alcotest.(check bool) "contains table"
    true (let _ = Str.search_forward (Str.regexp "| File |") content 0 in true)

(** Test manifest with prefix_kind=true *)
let test_manifest_prefixed () =
  let definitions = [
    { name = "Foo"; kind = Class; start_line = 1; end_line = 5 };
    { name = "bar"; kind = Function; start_line = 7; end_line = 10 };
  ] in
  let (content, _) = Render.manifest ~format:"yaml" ~source_name:"test.py" ~prefix_kind:true ~definitions in
  Alcotest.(check bool) "contains class_foo.py"
    true (let _ = Str.search_forward (Str.regexp "file: class_foo.py") content 0 in true);
  Alcotest.(check bool) "contains def_bar.py"
    true (let _ = Str.search_forward (Str.regexp "file: def_bar.py") content 0 in true)

let () =
  Alcotest.run "render"
    [ ( "render",
        [ Alcotest.test_case "plan_text" `Quick test_plan_text;
          Alcotest.test_case "plan_json" `Quick test_plan_json;
          Alcotest.test_case "extraction_text_dry_run" `Quick test_extraction_text_dry_run;
          Alcotest.test_case "extraction_text_written" `Quick test_extraction_text_written;
          Alcotest.test_case "extraction_json" `Quick test_extraction_json;
          Alcotest.test_case "error" `Quick test_error;
        ] );
      ( "manifest",
        [ Alcotest.test_case "yaml" `Quick test_manifest_yaml;
          Alcotest.test_case "json" `Quick test_manifest_json;
          Alcotest.test_case "md" `Quick test_manifest_md;
          Alcotest.test_case "prefixed" `Quick test_manifest_prefixed;
        ] )
    ]
