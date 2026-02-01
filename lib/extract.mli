(** Source code extraction using tree-sitter.

    This module provides functions to extract top-level definitions from
    Python source code. It uses tree-sitter CLI as the parsing backend,
    with the compiled python.dylib grammar.

    All line numbers in output are 1-indexed (matching Python/editor conventions).
*)

open Types

val extract_definitions : string -> definition list
(** [extract_definitions source] extracts all top-level class and function
    definitions from [source] Python code.

    Returns definitions sorted by start_line (ascending).

    Example:
    {[
      let defs = extract_definitions "class Foo:\n    pass\n" in
      (* [ { name = "Foo"; kind = Class; start_line = 1; end_line = 2 } ] *)
    ]}

    @raise Failure if tree-sitter parsing fails *)

(** Result of import extraction with metadata about skipped content *)
type import_result = {
  lines : string list;
  skipped_docstring : bool;
  skipped_pragmas : bool;
}

val extract_imports_full : ?keep_pragmas:bool -> string list -> import_result
(** [extract_imports_full ?keep_pragmas lines] extracts the import block
    from the beginning of a Python source file, with metadata.

    Includes:
    - Shebangs (#!/...)
    - import and from statements
    - Multi-line imports (parenthesized)
    - TYPE_CHECKING blocks

    Skips by default:
    - Module docstrings (tracked in [skipped_docstring])
    - Pragma comments like [# mypy:], [# type:] (tracked in [skipped_pragmas])

    @param keep_pragmas If true, pragma comments are included (default: false)
*)

val extract_imports : string list -> string list
(** Simple version of [extract_imports_full] for backwards compatibility.
    Returns just the lines, skipping docstrings and pragmas. *)

val extract_one : string -> string -> extraction_result option
(** [extract_one source name] extracts a single definition by name from source.

    Returns the extracted definition as an output_file and the remaining source.
    Returns None if the definition is not found.

    The extracted file includes:
    - Import block from the original source
    - Any comments immediately preceding the definition
    - The definition itself

    Example:
    {[
      let result = extract_one "class Foo:\n    pass\n" "Foo" in
      (* Some { extracted = { relative_path = "foo.py"; content = "..." };
               remainder = "" } *)
    ]}
*)
