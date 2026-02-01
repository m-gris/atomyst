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

(** Represents a parsed import statement *)
type parsed_import = {
  module_path : string;  (** The module being imported from *)
  name : string;         (** The name being imported (or alias if using 'as') *)
  is_relative : bool;    (** True if relative import (starts with .) *)
}

val parse_import_names : string list -> parsed_import list
(** [parse_import_names import_lines] parses import lines and extracts
    the names being imported along with their source modules.

    Used to detect potential re-exports: names that are imported but not
    defined in the source file. After atomization, these won't be available
    from the generated __init__.py, which may break consumers that relied
    on them as re-exports. *)

val adjust_relative_imports : depth_delta:int -> string list -> string list

val find_sibling_references : all_defns:Types.definition list -> target_defn:Types.definition -> defn_content:string -> string list
(** [find_sibling_references ~all_defns ~target_defn ~defn_content] finds
    names of sibling definitions that are referenced in [defn_content].
    Uses word boundary matching to detect references. *)

val find_constant_references : constant_names:string list -> defn_content:string -> string list
(** [find_constant_references ~constant_names ~defn_content] finds which
    constant names are referenced in [defn_content].
    Uses word boundary matching to detect references.
    Returns the subset of [constant_names] that appear in [defn_content]. *)

val generate_sibling_imports : string list -> string list
(** [generate_sibling_imports names] generates import lines for sibling modules.
    Returns lines like ["from .sibling_module import SiblingClass\n"]. *)
(** [adjust_relative_imports ~depth_delta lines] adjusts relative imports by
    adding [depth_delta] dots to each relative import.

    This is needed when extracting definitions to a subdirectory.
    For example, when extracting [foo.py] to [foo/bar.py], relative imports
    in [foo.py] that reference siblings need an extra dot to work from
    the subdirectory.

    Examples with [depth_delta=1]:
    - ["from .common import X"] becomes ["from ..common import X"]
    - ["from . import Y"] becomes ["from .. import Y"]
    - ["import foo"] is unchanged (not a relative import)
*)

val extract_one : ?depth_delta:int -> string -> string -> extraction_result option
(** [extract_one ?depth_delta source name] extracts a single definition by name from source.

    Returns the extracted definition as an output_file and the remaining source.
    Returns None if the definition is not found.

    @param depth_delta Number of dots to add to relative imports (default: 0).
           Use 1 when extracting to a subdirectory.

    The extracted file includes:
    - Import block from the original source (adjusted for depth if specified)
    - Any comments immediately preceding the definition
    - The definition itself

    Example:
    {[
      let result = extract_one "class Foo:\n    pass\n" "Foo" in
      (* Some { extracted = { relative_path = "foo.py"; content = "..." };
               remainder = "" } *)
    ]}
*)
