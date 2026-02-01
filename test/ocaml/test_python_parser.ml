(** Tests for Python_parser module.

    Tests the pyre-ast based Python import parsing.
*)

open Atomyst

(** Simple absolute import *)
let test_simple_import () =
  let source = "import os" in
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "one import" 1 (List.length imports);
  match List.hd imports with
  | Python_parser.Import { names; _ } ->
    Alcotest.(check int) "one name" 1 (List.length names);
    Alcotest.(check string) "name is os" "os" (List.hd names).name;
    Alcotest.(check bool) "no alias" true ((List.hd names).asname = None)
  | _ -> Alcotest.fail "expected Import, got ImportFrom"

(** Multiple imports on one line *)
let test_multiple_imports () =
  let source = "import os, sys, re" in
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "one import stmt" 1 (List.length imports);
  match List.hd imports with
  | Python_parser.Import { names; _ } ->
    let names_str = List.map (fun a -> a.Python_parser.name) names in
    Alcotest.(check (list string)) "three names" ["os"; "sys"; "re"] names_str
  | _ -> Alcotest.fail "expected Import"

(** Import with alias *)
let test_import_alias () =
  let source = "import numpy as np" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.Import { names; _ } ->
    let alias = List.hd names in
    Alcotest.(check string) "name" "numpy" alias.name;
    Alcotest.(check (option string)) "asname" (Some "np") alias.asname
  | _ -> Alcotest.fail "expected Import"

(** Simple from import *)
let test_from_import () =
  let source = "from typing import Optional, List" in
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "one import" 1 (List.length imports);
  match List.hd imports with
  | Python_parser.ImportFrom { module_; names; level; _ } ->
    Alcotest.(check (option string)) "module" (Some "typing") module_;
    Alcotest.(check int) "level 0" 0 level;
    let names_str = List.map (fun a -> a.Python_parser.name) names in
    Alcotest.(check (list string)) "two names" ["Optional"; "List"] names_str
  | _ -> Alcotest.fail "expected ImportFrom"

(** Relative import single dot *)
let test_relative_single_dot () =
  let source = "from .models import User" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.ImportFrom { module_; level; _ } ->
    Alcotest.(check (option string)) "module" (Some "models") module_;
    Alcotest.(check int) "level 1" 1 level
  | _ -> Alcotest.fail "expected ImportFrom"

(** Relative import double dot *)
let test_relative_double_dot () =
  let source = "from ..utils.helpers import log_msg" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.ImportFrom { module_; level; _ } ->
    Alcotest.(check (option string)) "module" (Some "utils.helpers") module_;
    Alcotest.(check int) "level 2" 2 level
  | _ -> Alcotest.fail "expected ImportFrom"

(** from . import X (no module name) *)
let test_from_dot_import () =
  let source = "from . import models" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.ImportFrom { module_; level; names; _ } ->
    Alcotest.(check (option string)) "no module" None module_;
    Alcotest.(check int) "level 1" 1 level;
    Alcotest.(check string) "name" "models" (List.hd names).name
  | _ -> Alcotest.fail "expected ImportFrom"

(** Multi-line import (GitHub #13) *)
let test_multiline_import () =
  let source = {|from typing import (
    Optional,
    List,
    Dict,
)|} in
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "one import" 1 (List.length imports);
  match List.hd imports with
  | Python_parser.ImportFrom { names; loc; _ } ->
    Alcotest.(check int) "three names" 3 (List.length names);
    (* Check location spans multiple lines *)
    Alcotest.(check int) "start line" 0 loc.start_line;
    Alcotest.(check bool) "spans lines" true (loc.end_line > loc.start_line)
  | _ -> Alcotest.fail "expected ImportFrom"

(** Location accuracy *)
let test_location () =
  let source = "from pkg import Foo" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.ImportFrom { loc; _ } ->
    (* pyre-ast uses 1-indexed lines, we convert to 0-indexed *)
    Alcotest.(check int) "start line" 0 loc.start_line;
    Alcotest.(check int) "start col" 0 loc.start_col;
    Alcotest.(check int) "end line" 0 loc.end_line
  | _ -> Alcotest.fail "expected ImportFrom"

(** From import with alias *)
let test_from_import_alias () =
  let source = "from pydantic import Field as F" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.ImportFrom { names; _ } ->
    let alias = List.hd names in
    Alcotest.(check string) "name" "Field" alias.name;
    Alcotest.(check (option string)) "asname" (Some "F") alias.asname
  | _ -> Alcotest.fail "expected ImportFrom"

(** Star import *)
let test_star_import () =
  let source = "from module import *" in
  let imports = Python_parser.extract_imports source in
  match List.hd imports with
  | Python_parser.ImportFrom { names; _ } ->
    Alcotest.(check int) "one name" 1 (List.length names);
    Alcotest.(check string) "star" "*" (List.hd names).name
  | _ -> Alcotest.fail "expected ImportFrom"

(** Multiple import statements *)
let test_multiple_statements () =
  let source = {|import os
from typing import Optional
from .models import User|} in
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "three imports" 3 (List.length imports)

(** Non-import code doesn't produce imports *)
let test_no_imports () =
  let source = {|def foo():
    pass

class Bar:
    x = 1|} in
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "no imports" 0 (List.length imports)

(** Parse error returns empty list *)
let test_parse_error () =
  let source = "from import" in (* syntax error *)
  let imports = Python_parser.extract_imports source in
  Alcotest.(check int) "empty on error" 0 (List.length imports)

(** Parse error with error message *)
let test_parse_error_with_message () =
  let source = "from import" in
  let imports, err = Python_parser.extract_imports_with_error source in
  Alcotest.(check int) "empty on error" 0 (List.length imports);
  Alcotest.(check bool) "has error" true (Option.is_some err)

let () =
  Alcotest.run "python_parser"
    [ ( "import",
        [ Alcotest.test_case "simple" `Quick test_simple_import;
          Alcotest.test_case "multiple" `Quick test_multiple_imports;
          Alcotest.test_case "alias" `Quick test_import_alias;
        ] );
      ( "from_import",
        [ Alcotest.test_case "simple" `Quick test_from_import;
          Alcotest.test_case "relative_single_dot" `Quick test_relative_single_dot;
          Alcotest.test_case "relative_double_dot" `Quick test_relative_double_dot;
          Alcotest.test_case "from_dot" `Quick test_from_dot_import;
          Alcotest.test_case "multiline" `Quick test_multiline_import;
          Alcotest.test_case "alias" `Quick test_from_import_alias;
          Alcotest.test_case "star" `Quick test_star_import;
        ] );
      ( "location",
        [ Alcotest.test_case "basic" `Quick test_location;
        ] );
      ( "multiple",
        [ Alcotest.test_case "statements" `Quick test_multiple_statements;
          Alcotest.test_case "no_imports" `Quick test_no_imports;
        ] );
      ( "errors",
        [ Alcotest.test_case "parse_error" `Quick test_parse_error;
          Alcotest.test_case "error_message" `Quick test_parse_error_with_message;
        ] );
    ]
