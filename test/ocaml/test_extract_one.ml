(** Tests for Extract.extract_one.

    Uses fixture 10_incremental to verify extraction behavior.
*)

open Atomyst

(** Read a fixture file *)
let read_fixture path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

(** Test extracting Foo from input *)
let test_extract_foo () =
  let source = read_fixture "test/fixtures/10_incremental/input.py" in
  let expected_content = read_fixture "test/fixtures/10_incremental/extract_foo/expected_foo.py" in
  let expected_remainder = read_fixture "test/fixtures/10_incremental/extract_foo/expected_remainder.py" in

  match Extract.extract_one source "Foo" with
  | None -> Alcotest.fail "Expected Some, got None"
  | Some result ->
    Alcotest.(check string) "filename"
      "foo.py" result.extracted.relative_path;
    Alcotest.(check string) "extracted content"
      expected_content result.extracted.content;
    Alcotest.(check string) "remainder"
      expected_remainder result.remainder

(** Test extracting Bar from input *)
let test_extract_bar () =
  let source = read_fixture "test/fixtures/10_incremental/input.py" in
  let expected_content = read_fixture "test/fixtures/10_incremental/extract_bar/expected_bar.py" in
  let expected_remainder = read_fixture "test/fixtures/10_incremental/extract_bar/expected_remainder.py" in

  match Extract.extract_one source "Bar" with
  | None -> Alcotest.fail "Expected Some, got None"
  | Some result ->
    Alcotest.(check string) "filename"
      "bar.py" result.extracted.relative_path;
    Alcotest.(check string) "extracted content"
      expected_content result.extracted.content;
    Alcotest.(check string) "remainder"
      expected_remainder result.remainder

(** Test extracting non-existent definition *)
let test_extract_not_found () =
  let source = read_fixture "test/fixtures/10_incremental/input.py" in
  match Extract.extract_one source "NonExistent" with
  | None -> ()
  | Some _ -> Alcotest.fail "Expected None, got Some"

let () =
  Alcotest.run "extract_one"
    [ ( "extract_one",
        [ Alcotest.test_case "extract_foo" `Quick test_extract_foo;
          Alcotest.test_case "extract_bar" `Quick test_extract_bar;
          Alcotest.test_case "not_found" `Quick test_extract_not_found;
        ] )
    ]
