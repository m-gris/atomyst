(** Pure OCaml Python parsing via pyre-ast.

    Replaces tree-sitter + regex parsing with typed AST.
    Uses CPython under the hood for 100% parsing fidelity.
*)

(** Location in source file (0-indexed for compatibility with existing code) *)
type location = {
  start_line : int;
  start_col : int;
  end_line : int;
  end_col : int;
}

(** An imported name with optional alias *)
type import_alias = {
  name : string;           (** The name being imported *)
  asname : string option;  (** Optional "as X" alias *)
  loc : location;          (** Location of this alias *)
}

(** A Python import statement *)
type import_stmt =
  | Import of {
      names : import_alias list;  (** import X, Y, Z *)
      loc : location;
    }
  | ImportFrom of {
      module_ : string option;    (** None for "from . import X" *)
      names : import_alias list;  (** The imported names *)
      level : int;                (** Number of dots (0 = absolute) *)
      loc : location;
    }

(** Parse Python source and extract all import statements.
    Returns empty list on parse error (non-fatal). *)
val extract_imports : string -> import_stmt list

(** Parse Python source and extract all import statements with errors.
    Returns (imports, error_opt) where error_opt is set on parse failure. *)
val extract_imports_with_error : string -> import_stmt list * string option

(** A module-level constant (Assign, AnnAssign, or TypeAlias).
    Excludes: dunder names (__all__, __name__), augmented assignments (+=). *)
type module_constant = {
  name : string;        (** The assigned name *)
  loc : location;       (** Location in source *)
  source_text : string; (** Raw source text of the assignment *)
}

(** Extract module-level constant definitions from Python source.
    Returns empty list on parse error (non-fatal).
    Excludes logger bindings (see extract_logger_bindings). *)
val extract_constants : string -> module_constant list

(** A logger binding: logger = logging.getLogger(__name__).
    These depend on __name__ and must be replicated per-file,
    not extracted to _constants.py. *)
type logger_binding = {
  var_name : string;    (** The variable name (e.g., "logger", "log") *)
  loc : location;       (** Location in source *)
  source_text : string; (** Raw source text of the assignment *)
}

(** Extract logger bindings from Python source.
    These are assignments like: logger = logging.getLogger(__name__)
    They depend on __name__ and must be replicated in each extracted file
    that uses the logger variable. *)
val extract_logger_bindings : string -> logger_binding list

(** A top-level definition extracted from source *)
type extracted_definition = {
  name : string;
  kind : Types.definition_kind;
  loc : location;
}

(** Extract top-level class and function definitions from Python source.
    Returns definitions sorted by start line (ascending).
    - FunctionDef -> Types.Function
    - AsyncFunctionDef -> Types.AsyncFunction
    - ClassDef -> Types.Class
    Only top-level definitions (column 0) are included.
    Decorated definitions include the decorator range. *)
val extract_definitions : string -> extracted_definition list
