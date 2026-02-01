(** Tests for Extract.extract_imports.

    These test cases are ported from the Python test suite (TestExtractImports).
*)

open Atomyst

(** Test simple imports *)
let test_simple_imports () =
  let lines = [
    "import os\n";
    "from pathlib import Path\n";
    "\n";
    "class Foo:\n";
    "    pass\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check bool) "import os in imports"
    true (List.mem "import os\n" imports);
  Alcotest.(check bool) "from pathlib in imports"
    true (List.mem "from pathlib import Path\n" imports)

(** Test multiline import with parentheses *)
let test_multiline_import () =
  let lines = [
    "from typing import (\n";
    "    List,\n";
    "    Dict,\n";
    ")\n";
    "\n";
    "class Foo:\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check int) "5 import lines (4 import + blank)"
    5 (List.length imports)

(** Test module docstring is skipped (not copied to extracted files) *)
let test_module_docstring () =
  let lines = [
    {|"""Module docstring."""|} ^ "\n";
    "\n";
    "import os\n";
    "\n";
    "class Foo:\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check bool) "docstring NOT in imports"
    false (List.mem ({|"""Module docstring."""|} ^ "\n") imports);
  Alcotest.(check bool) "import os in imports"
    true (List.mem "import os\n" imports)

(** Test shebang is preserved but docstring is skipped *)
let test_shebang () =
  let lines = [
    "#!/usr/bin/env python3\n";
    {|"""Docstring."""|} ^ "\n";
    "\n";
    "import os\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check bool) "shebang in imports"
    true (List.mem "#!/usr/bin/env python3\n" imports);
  Alcotest.(check bool) "docstring NOT in imports"
    false (List.mem ({|"""Docstring."""|} ^ "\n") imports);
  Alcotest.(check bool) "import os in imports"
    true (List.mem "import os\n" imports)

(** Test TYPE_CHECKING block *)
let test_type_checking () =
  let lines = [
    "from typing import TYPE_CHECKING\n";
    "\n";
    "if TYPE_CHECKING:\n";
    "    from heavy import HeavyType\n";
    "    from another import AnotherType\n";
    "\n";
    "class Foo:\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check bool) "if TYPE_CHECKING in imports"
    true (List.mem "if TYPE_CHECKING:\n" imports);
  Alcotest.(check bool) "HeavyType import in imports"
    true (List.mem "    from heavy import HeavyType\n" imports);
  Alcotest.(check bool) "AnotherType import in imports"
    true (List.mem "    from another import AnotherType\n" imports)

(** Test multi-line docstring and pragmas are skipped *)
let test_multiline_docstring () =
  let lines = [
    {|# mypy: disable-error-code="explicit-any"|} ^ "\n";
    {|"""|} ^ "\n";
    "Multi-line docstring\n";
    "spanning many lines.\n";
    {|"""|} ^ "\n";
    "\n";
    "import hashlib\n";
    "from typing import List\n";
    "\n";
    "class Foo:\n";
  ] in
  let imports = Extract.extract_imports lines in
  (* Pragmas and docstrings are skipped *)
  Alcotest.(check bool) "pragma NOT in imports"
    false (List.mem ({|# mypy: disable-error-code="explicit-any"|} ^ "\n") imports);
  Alcotest.(check bool) "docstring opening NOT in imports"
    false (List.mem ({|"""|} ^ "\n") imports);
  Alcotest.(check bool) "docstring middle NOT in imports"
    false (List.mem "Multi-line docstring\n" imports);
  (* Actual imports are preserved *)
  Alcotest.(check bool) "import hashlib in imports"
    true (List.mem "import hashlib\n" imports);
  Alcotest.(check bool) "from typing in imports"
    true (List.mem "from typing import List\n" imports)

(** Test relative import depth adjustment - single dot becomes double dot *)
let test_adjust_relative_single_dot () =
  let lines = [
    "from .common import X\n";
    "from .utils import helper\n";
  ] in
  let adjusted = Extract.adjust_relative_imports ~depth_delta:1 lines in
  Alcotest.(check string) "single dot becomes double"
    "from ..common import X\n" (List.nth adjusted 0);
  Alcotest.(check string) "single dot becomes double (utils)"
    "from ..utils import helper\n" (List.nth adjusted 1)

(** Test relative import depth adjustment - double dot becomes triple *)
let test_adjust_relative_double_dot () =
  let lines = [
    "from ..parent import Y\n";
  ] in
  let adjusted = Extract.adjust_relative_imports ~depth_delta:1 lines in
  Alcotest.(check string) "double dot becomes triple"
    "from ...parent import Y\n" (List.nth adjusted 0)

(** Test relative import depth adjustment - bare dot import *)
let test_adjust_relative_bare_dot () =
  let lines = [
    "from . import foo\n";
  ] in
  let adjusted = Extract.adjust_relative_imports ~depth_delta:1 lines in
  Alcotest.(check string) "bare dot becomes double"
    "from .. import foo\n" (List.nth adjusted 0)

(** Test absolute imports are unchanged *)
let test_adjust_absolute_unchanged () =
  let lines = [
    "import os\n";
    "from typing import List\n";
    "from pathlib import Path\n";
  ] in
  let adjusted = Extract.adjust_relative_imports ~depth_delta:1 lines in
  Alcotest.(check string) "import os unchanged"
    "import os\n" (List.nth adjusted 0);
  Alcotest.(check string) "from typing unchanged"
    "from typing import List\n" (List.nth adjusted 1);
  Alcotest.(check string) "from pathlib unchanged"
    "from pathlib import Path\n" (List.nth adjusted 2)

(** Test depth_delta=0 makes no changes *)
let test_adjust_zero_delta () =
  let lines = [
    "from .common import X\n";
  ] in
  let adjusted = Extract.adjust_relative_imports ~depth_delta:0 lines in
  Alcotest.(check string) "zero delta = no change"
    "from .common import X\n" (List.nth adjusted 0)

(** Test depth_delta=2 adds two dots *)
let test_adjust_delta_two () =
  let lines = [
    "from .common import X\n";
  ] in
  let adjusted = Extract.adjust_relative_imports ~depth_delta:2 lines in
  Alcotest.(check string) "delta 2 adds two dots"
    "from ...common import X\n" (List.nth adjusted 0)

(** Test finding sibling references in definition content *)
let test_find_sibling_basic () =
  let open Types in
  let all_defns = [
    { name = "Foo"; kind = Class; start_line = 1; end_line = 3 };
    { name = "Bar"; kind = Class; start_line = 5; end_line = 8 };
    { name = "helper"; kind = Function; start_line = 10; end_line = 12 };
  ] in
  let target = { name = "Bar"; kind = Class; start_line = 5; end_line = 8 } in
  let content = "class Bar:\n    foo: Foo = None\n    def use(self): helper()\n" in
  let refs = Extract.find_sibling_references ~all_defns ~target_defn:target ~defn_content:content in
  Alcotest.(check int) "found 2 siblings" 2 (List.length refs);
  Alcotest.(check bool) "Foo referenced" true (List.mem "Foo" refs);
  Alcotest.(check bool) "helper referenced" true (List.mem "helper" refs)

(** Test that self-references are excluded *)
let test_find_sibling_excludes_self () =
  let open Types in
  let all_defns = [
    { name = "Foo"; kind = Class; start_line = 1; end_line = 3 };
  ] in
  let target = { name = "Foo"; kind = Class; start_line = 1; end_line = 3 } in
  let content = "class Foo:\n    self_ref: Foo = None\n" in
  let refs = Extract.find_sibling_references ~all_defns ~target_defn:target ~defn_content:content in
  Alcotest.(check int) "self not referenced" 0 (List.length refs)

(** Test generate_sibling_imports creates correct import lines *)
let test_generate_sibling_imports () =
  let imports = Extract.generate_sibling_imports ["Foo"; "BarBaz"] in
  Alcotest.(check int) "2 imports generated" 2 (List.length imports);
  Alcotest.(check string) "Foo import"
    "from .foo import Foo\n" (List.nth imports 0);
  Alcotest.(check string) "BarBaz import"
    "from .bar_baz import BarBaz\n" (List.nth imports 1)

(** Test parse_import_names with single-line import *)
let test_parse_import_names_single_line () =
  let lines = ["from pydantic import Field\n"] in
  let parsed = Extract.parse_import_names lines in
  Alcotest.(check int) "1 import parsed" 1 (List.length parsed);
  let imp = List.hd parsed in
  Alcotest.(check string) "module is pydantic" "pydantic" imp.Extract.module_path;
  Alcotest.(check string) "name is Field" "Field" imp.Extract.name

(** Test parse_import_names with multi-line parenthesized import (GitHub #12) *)
let test_parse_import_names_multiline () =
  let lines = [
    "from pydantic import (\n";
    "    BaseModel,\n";
    "    Field,\n";
    ")\n";
  ] in
  let parsed = Extract.parse_import_names lines in
  Alcotest.(check int) "2 imports parsed" 2 (List.length parsed);
  let names = List.map (fun (p : Extract.parsed_import) -> p.name) parsed in
  Alcotest.(check bool) "BaseModel found" true (List.mem "BaseModel" names);
  Alcotest.(check bool) "Field found" true (List.mem "Field" names)

(** Test parse_import_names with mixed single and multi-line imports (GitHub #12) *)
let test_parse_import_names_mixed () =
  let lines = [
    "from beartype import beartype\n";
    "from pydantic import (\n";
    "    BaseModel,\n";
    "    Field,\n";
    "    HttpUrl,\n";
    ")\n";
  ] in
  let parsed = Extract.parse_import_names lines in
  Alcotest.(check int) "4 imports parsed" 4 (List.length parsed);
  let names = List.map (fun (p : Extract.parsed_import) -> p.name) parsed in
  Alcotest.(check bool) "beartype found" true (List.mem "beartype" names);
  Alcotest.(check bool) "BaseModel found" true (List.mem "BaseModel" names);
  Alcotest.(check bool) "Field found" true (List.mem "Field" names);
  Alcotest.(check bool) "HttpUrl found" true (List.mem "HttpUrl" names)

(** Test parse_import_names with trailing comments (real-world case) *)
let test_parse_import_names_with_comments () =
  let lines = [
    "from beartype import beartype  # some comment\n";
    "from pydantic import (  # another comment\n";
    "    BaseModel,\n";
    "    Field,\n";
    ")\n";
  ] in
  let parsed = Extract.parse_import_names lines in
  Alcotest.(check int) "3 imports parsed" 3 (List.length parsed);
  let names = List.map (fun (p : Extract.parsed_import) -> p.name) parsed in
  Alcotest.(check bool) "beartype found" true (List.mem "beartype" names);
  Alcotest.(check bool) "BaseModel found" true (List.mem "BaseModel" names);
  Alcotest.(check bool) "Field found" true (List.mem "Field" names)

(** === Tests for find_constant_references === *)

(** Basic detection of constants in definition content *)
let test_find_constant_refs_basic () =
  let constant_names = ["FOO"; "BAR"; "BAZ"] in
  let content = "class Query:\n    mapping = FOO\n    other = BAR\n" in
  let refs = Extract.find_constant_references ~constant_names ~defn_content:content in
  Alcotest.(check int) "found 2 constants" 2 (List.length refs);
  Alcotest.(check bool) "FOO found" true (List.mem "FOO" refs);
  Alcotest.(check bool) "BAR found" true (List.mem "BAR" refs);
  Alcotest.(check bool) "BAZ not found" false (List.mem "BAZ" refs)

(** No false positives from substrings *)
let test_find_constant_refs_no_substring () =
  let constant_names = ["FOO"] in
  let content = "FOOBAR = 1\n" in
  let refs = Extract.find_constant_references ~constant_names ~defn_content:content in
  Alcotest.(check int) "FOO not in FOOBAR" 0 (List.length refs)

(** Empty constants list *)
let test_find_constant_refs_empty () =
  let constant_names = [] in
  let content = "class Foo:\n    x = ANYTHING\n" in
  let refs = Extract.find_constant_references ~constant_names ~defn_content:content in
  Alcotest.(check int) "empty input -> empty output" 0 (List.length refs)

(** Constant in type annotation *)
let test_find_constant_refs_type_annotation () =
  let constant_names = ["SqlType"; "MAPPING"] in
  let content = "def convert(t: SqlType) -> str:\n    return MAPPING[t]\n" in
  let refs = Extract.find_constant_references ~constant_names ~defn_content:content in
  Alcotest.(check int) "found both" 2 (List.length refs)

let () =
  Alcotest.run "extract_imports"
    [ ( "extract_imports",
        [ Alcotest.test_case "simple_imports" `Quick test_simple_imports;
          Alcotest.test_case "multiline_import" `Quick test_multiline_import;
          Alcotest.test_case "module_docstring" `Quick test_module_docstring;
          Alcotest.test_case "shebang" `Quick test_shebang;
          Alcotest.test_case "type_checking" `Quick test_type_checking;
          Alcotest.test_case "multiline_docstring" `Quick test_multiline_docstring;
        ] );
      ( "adjust_relative_imports",
        [ Alcotest.test_case "single_dot" `Quick test_adjust_relative_single_dot;
          Alcotest.test_case "double_dot" `Quick test_adjust_relative_double_dot;
          Alcotest.test_case "bare_dot" `Quick test_adjust_relative_bare_dot;
          Alcotest.test_case "absolute_unchanged" `Quick test_adjust_absolute_unchanged;
          Alcotest.test_case "zero_delta" `Quick test_adjust_zero_delta;
          Alcotest.test_case "delta_two" `Quick test_adjust_delta_two;
        ] );
      ( "sibling_imports",
        [ Alcotest.test_case "find_basic" `Quick test_find_sibling_basic;
          Alcotest.test_case "excludes_self" `Quick test_find_sibling_excludes_self;
          Alcotest.test_case "generate_imports" `Quick test_generate_sibling_imports;
        ] );
      ( "parse_import_names",
        [ Alcotest.test_case "single_line" `Quick test_parse_import_names_single_line;
          Alcotest.test_case "multiline" `Quick test_parse_import_names_multiline;
          Alcotest.test_case "mixed" `Quick test_parse_import_names_mixed;
          Alcotest.test_case "with_comments" `Quick test_parse_import_names_with_comments;
        ] );
      ( "constant_references",
        [ Alcotest.test_case "basic" `Quick test_find_constant_refs_basic;
          Alcotest.test_case "no_substring" `Quick test_find_constant_refs_no_substring;
          Alcotest.test_case "empty" `Quick test_find_constant_refs_empty;
          Alcotest.test_case "type_annotation" `Quick test_find_constant_refs_type_annotation;
        ] )
    ]
