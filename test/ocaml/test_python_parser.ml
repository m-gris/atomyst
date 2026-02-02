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
    let names_str = List.map (fun (a : Python_parser.import_alias) -> a.name) names in
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
    let names_str = List.map (fun (a : Python_parser.import_alias) -> a.name) names in
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

(** === Tests for extract_constants === *)

(** Simple assignment: NAME = value *)
let test_simple_assign () =
  let source = "FOO = 42" in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "one constant" 1 (List.length constants);
  Alcotest.(check string) "name" "FOO" (List.hd constants).name

(** Annotated assignment: NAME: type = value *)
let test_annotated_assign () =
  let source = {|SQL_TYPES: Dict[str, str] = {"int": "INTEGER"}|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "one constant" 1 (List.length constants);
  Alcotest.(check string) "name" "SQL_TYPES" (List.hd constants).name

(** Source text is captured correctly *)
let test_source_text () =
  let source = {|FOO = 42
BAR: int = 100|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "two constants" 2 (List.length constants);
  let foo = List.hd constants in
  let bar = List.nth constants 1 in
  Alcotest.(check string) "FOO source" "FOO = 42\n" foo.source_text;
  Alcotest.(check string) "BAR source" "BAR: int = 100\n" bar.source_text

(** Multi-line constant source text *)
let test_source_text_multiline () =
  let source = {|MAPPING = {
    "a": 1,
    "b": 2,
}|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "one constant" 1 (List.length constants);
  let c = List.hd constants in
  Alcotest.(check bool) "spans multiple lines" true
    (String.length c.source_text > 20)

(** Annotated without value: NAME: type *)
let test_annotated_no_value () =
  let source = "logger: Logger" in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "one constant" 1 (List.length constants);
  Alcotest.(check string) "name" "logger" (List.hd constants).name

(** Multiple constants *)
let test_multiple_constants () =
  let source = {|FOO = 1
BAR: int = 2
BAZ = "hello"|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "three constants" 3 (List.length constants);
  let names = List.map (fun (c : Python_parser.module_constant) -> c.name) constants in
  Alcotest.(check (list string)) "names" ["FOO"; "BAR"; "BAZ"] names

(** Dunder names are skipped *)
let test_skip_dunder () =
  let source = {|__all__ = ["Foo"]
__version__ = "1.0"
NORMAL = 42|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "only NORMAL" 1 (List.length constants);
  Alcotest.(check string) "name" "NORMAL" (List.hd constants).name

(** Tuple unpacking is skipped (not simple Name target) *)
let test_skip_tuple_unpack () =
  let source = {|a, b = 1, 2
SIMPLE = 3|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "only SIMPLE" 1 (List.length constants);
  Alcotest.(check string) "name" "SIMPLE" (List.hd constants).name

(** Attribute assignment is skipped *)
let test_skip_attribute () =
  let source = {|self.foo = 1
MODULE = 2|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "only MODULE" 1 (List.length constants)

(** Class/function definitions are not constants *)
let test_skip_definitions () =
  let source = {|CONST = 1

class Foo:
    pass

def bar():
    pass|} in
  let constants = Python_parser.extract_constants source in
  Alcotest.(check int) "only CONST" 1 (List.length constants)

(** Location is correct *)
let test_constant_location () =
  let source = {|# comment
CONST = 42|} in
  let constants = Python_parser.extract_constants source in
  let c = List.hd constants in
  Alcotest.(check int) "line 1 (0-indexed)" 1 c.loc.start_line

(** === Tests for extract_logger_bindings === *)

(** Detects logger = logging.getLogger(__name__) *)
let test_logger_binding_basic () =
  let source = {|import logging
logger = logging.getLogger(__name__)|} in
  let bindings = Python_parser.extract_logger_bindings source in
  Alcotest.(check int) "one binding" 1 (List.length bindings);
  let lb = List.hd bindings in
  Alcotest.(check string) "var_name" "logger" lb.var_name;
  Alcotest.(check bool) "source contains getLogger" true
    (String.length lb.source_text > 0 &&
     String.sub lb.source_text 0 6 = "logger")

(** Detects with different variable name *)
let test_logger_binding_different_name () =
  let source = {|import logging
log = logging.getLogger(__name__)|} in
  let bindings = Python_parser.extract_logger_bindings source in
  Alcotest.(check int) "one binding" 1 (List.length bindings);
  Alcotest.(check string) "var_name is log" "log" (List.hd bindings).var_name

(** Constants should NOT include logger bindings *)
let test_constants_exclude_logger () =
  let source = {|import logging
CONST = 42
logger = logging.getLogger(__name__)
OTHER = "value"|} in
  let constants = Python_parser.extract_constants source in
  let names = List.map (fun (c : Python_parser.module_constant) -> c.name) constants in
  Alcotest.(check int) "two constants" 2 (List.length constants);
  Alcotest.(check bool) "has CONST" true (List.mem "CONST" names);
  Alcotest.(check bool) "has OTHER" true (List.mem "OTHER" names);
  Alcotest.(check bool) "no logger" false (List.mem "logger" names)

(** No logger bindings when pattern doesn't match *)
let test_logger_binding_no_match () =
  let source = {|import logging
logger = logging.getLogger("explicit_name")
CONST = 42|} in
  let bindings = Python_parser.extract_logger_bindings source in
  Alcotest.(check int) "no bindings" 0 (List.length bindings);
  (* But it should still be a constant since it doesn't use __name__ *)
  let constants = Python_parser.extract_constants source in
  let names = List.map (fun (c : Python_parser.module_constant) -> c.name) constants in
  Alcotest.(check bool) "logger is constant" true (List.mem "logger" names)

(** Detects with alias like: import logging as log; x = log.getLogger(__name__) *)
let test_logger_binding_aliased_module () =
  let source = {|import logging as lg
mylogger = lg.getLogger(__name__)|} in
  let bindings = Python_parser.extract_logger_bindings source in
  Alcotest.(check int) "one binding" 1 (List.length bindings);
  Alcotest.(check string) "var_name" "mylogger" (List.hd bindings).var_name

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
      ( "constants",
        [ Alcotest.test_case "simple_assign" `Quick test_simple_assign;
          Alcotest.test_case "annotated_assign" `Quick test_annotated_assign;
          Alcotest.test_case "source_text" `Quick test_source_text;
          Alcotest.test_case "source_text_multiline" `Quick test_source_text_multiline;
          Alcotest.test_case "annotated_no_value" `Quick test_annotated_no_value;
          Alcotest.test_case "multiple" `Quick test_multiple_constants;
          Alcotest.test_case "skip_dunder" `Quick test_skip_dunder;
          Alcotest.test_case "skip_tuple_unpack" `Quick test_skip_tuple_unpack;
          Alcotest.test_case "skip_attribute" `Quick test_skip_attribute;
          Alcotest.test_case "skip_definitions" `Quick test_skip_definitions;
          Alcotest.test_case "location" `Quick test_constant_location;
        ] );
      ( "logger_bindings",
        [ Alcotest.test_case "basic" `Quick test_logger_binding_basic;
          Alcotest.test_case "different_name" `Quick test_logger_binding_different_name;
          Alcotest.test_case "constants_exclude" `Quick test_constants_exclude_logger;
          Alcotest.test_case "no_match" `Quick test_logger_binding_no_match;
          Alcotest.test_case "aliased_module" `Quick test_logger_binding_aliased_module;
        ] );
    ]
