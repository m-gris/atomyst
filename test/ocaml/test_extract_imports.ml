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

(** Test module docstring is preserved *)
let test_module_docstring () =
  let lines = [
    {|"""Module docstring."""|} ^ "\n";
    "\n";
    "import os\n";
    "\n";
    "class Foo:\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check bool) "docstring in imports"
    true (List.mem ({|"""Module docstring."""|} ^ "\n") imports)

(** Test shebang and docstring *)
let test_shebang () =
  let lines = [
    "#!/usr/bin/env python3\n";
    {|"""Docstring."""|} ^ "\n";
    "\n";
    "import os\n";
  ] in
  let imports = Extract.extract_imports lines in
  Alcotest.(check bool) "shebang in imports"
    true (List.mem "#!/usr/bin/env python3\n" imports)

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

(** Test multi-line docstring *)
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
  Alcotest.(check bool) "opening docstring in imports"
    true (List.mem ({|"""|} ^ "\n") imports);
  Alcotest.(check bool) "docstring middle in imports"
    true (List.mem "Multi-line docstring\n" imports);
  Alcotest.(check bool) "import hashlib in imports"
    true (List.mem "import hashlib\n" imports);
  Alcotest.(check bool) "from typing in imports"
    true (List.mem "from typing import List\n" imports)

let () =
  Alcotest.run "extract_imports"
    [ ( "extract_imports",
        [ Alcotest.test_case "simple_imports" `Quick test_simple_imports;
          Alcotest.test_case "multiline_import" `Quick test_multiline_import;
          Alcotest.test_case "module_docstring" `Quick test_module_docstring;
          Alcotest.test_case "shebang" `Quick test_shebang;
          Alcotest.test_case "type_checking" `Quick test_type_checking;
          Alcotest.test_case "multiline_docstring" `Quick test_multiline_docstring;
        ] )
    ]
