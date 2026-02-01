(** Consumer import rewriting for atomization.

    When a file is atomized, consumers that imported "re-exports" break.
    This module detects such imports and rewrites them to use original sources.

    Example:
    - Before: [from .domain_models import Field, StrictBaseModel, Query]
    - After: [from pydantic import Field]
             [from .common import StrictBaseModel]
             [from .domain_models import Query]
*)

(** Classification of an imported name *)
type import_classification =
  | Definition    (** Name is defined in the target module *)
  | Reexport of { original_module : string }  (** Name is a re-export *)
  | Unknown       (** Cannot determine source *)

(** A single imported name with metadata *)
type import_name = {
  name : string;              (** The imported name (or alias) *)
  original_name : string;     (** Original name if aliased *)
  has_alias : bool;           (** True if "X as Y" syntax used *)
}

(** A parsed import statement from a consumer file *)
type consumer_import = {
  target_module : string;     (** Module being imported from *)
  names : import_name list;   (** Names being imported *)
  start_row : int;            (** 0-indexed start row *)
  start_col : int;            (** 0-indexed start column *)
  end_row : int;              (** 0-indexed end row *)
  end_col : int;              (** 0-indexed end column *)
  is_relative : bool;         (** True if relative import *)
  has_star : bool;            (** True if "from X import *" *)
}

(** A rewrite to apply to a file *)
type rewrite = {
  file_path : string;
  start_row : int;
  start_col : int;
  end_row : int;
  end_col : int;
  old_text : string;
  new_text : string;
}

(** Result of attempting to fix consumer imports *)
type fix_result =
  | Fixed of { rewrites : rewrite list; files_changed : int }
  | StarImportError of { file : string; line : int }
  | Error of string

val find_git_root : string -> string option
(** [find_git_root path] finds the git repository root containing [path].
    Returns None if not in a git repository. *)

val find_python_files : string -> string list
(** [find_python_files root] finds all Python files tracked by git.
    Uses [git ls-files] to respect .gitignore. *)

val module_path_of_file : root:string -> string -> string
(** [module_path_of_file ~root file] converts a file path to a Python module path.
    Example: "src/models/domain.py" -> "src.models.domain" *)

val resolve_relative_import : from_file:string -> module_ref:string -> string
(** [resolve_relative_import ~from_file ~module_ref] resolves a relative import.
    Example: resolve_relative_import ~from_file:"pkg/consumer.py" ~module_ref:".models"
             -> "pkg.models" *)

val find_imports_from_module :
  consumer_source:string ->
  target_module:string ->
  consumer_import list
(** [find_imports_from_module ~consumer_source ~target_module] finds all imports
    in [consumer_source] that import from [target_module]. *)

val classify_import_name :
  name:string ->
  defined_names:string list ->
  reexports:(string * string) list ->
  import_classification
(** [classify_import_name ~name ~defined_names ~reexports] determines
    if a name is a definition or a re-export.
    [reexports] is a list of (name, original_module) pairs. *)

val generate_replacement_imports :
  import:consumer_import ->
  classifications:(string * import_classification) list ->
  string
(** [generate_replacement_imports ~import ~classifications] generates
    the replacement import text for a consumer import. *)

val apply_rewrites : file_path:string -> rewrites:rewrite list -> unit
(** [apply_rewrites ~file_path ~rewrites] applies rewrites to a file atomically.
    Processes in reverse position order to preserve offsets. *)

val fix_consumer_imports :
  atomized_file:string ->
  defined_names:string list ->
  reexports:(string * string) list ->
  fix_result
(** [fix_consumer_imports ~atomized_file ~defined_names ~reexports] finds
    and fixes all consumer imports that reference the atomized module.
    Fails fast on star imports. *)
