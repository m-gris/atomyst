(** Lint atomized directories for prefix consistency.

    Verifies that filenames match their definition kinds.
    Pure analysis functions - I/O pushed to caller.
*)

open Types

(** A single lint issue found in a file *)
type lint_issue = {
  file_path : string;        (** Relative path within atomized dir *)
  expected_kinds : definition_kind list;  (** Kinds implied by filename prefix *)
  actual_kind : definition_kind;          (** Kind found in file *)
  definition_name : string;  (** Name of the definition *)
  line : int;                (** Line number (1-indexed) *)
}

(** Result of linting a single file *)
type file_result =
  | Clean                    (** File matches its prefix (or has no prefix) *)
  | Mismatch of lint_issue   (** Prefix doesn't match definition kind *)
  | NoDefinition             (** File has prefix but no definition found *)
  | ParseError of string     (** Could not parse the file *)

(** Result of linting a directory *)
type lint_result =
  | AllClean of int          (** All files clean, count of files checked *)
  | Issues of lint_issue list (** List of mismatches found *)
  | Error of string          (** Fatal error (e.g., dir doesn't exist) *)

val check_file : dir:string -> filename:string -> source:string -> file_result
(** Check a single file for prefix/kind consistency.

    Pure function: takes file contents, returns analysis result.

    @param dir Directory path (for error messages)
    @param filename Just the filename (e.g., "class_user.py")
    @param source File contents as string

    Returns:
    - [Clean] if no prefix or prefix matches definition kind
    - [Mismatch issue] if prefix implies different kind than found
    - [NoDefinition] if prefixed file contains no extractable definition
    - [ParseError msg] if source couldn't be parsed *)

val lint_directory : dir:string -> read_file:(string -> string option) -> lint_result
(** Lint all .py files in a directory.

    @param dir Directory path to lint
    @param read_file Function to read file contents (None if read fails)

    Skips special files (_constants.py, __init__.py).
    Returns aggregated results. *)
