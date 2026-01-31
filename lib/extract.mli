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
