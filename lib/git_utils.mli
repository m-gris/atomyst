(** Git utilities for safe file operations. *)

type safe_remove_result =
  | Safe
  | NotInRepo
  | NotTracked
  | HasUncommittedChanges

val check_safe_to_remove : string -> safe_remove_result
(** Check if a file can be safely removed.
    Returns [Safe] only if the file is in a git repo, tracked, and has no uncommitted changes. *)

val safe_remove_result_to_string : safe_remove_result -> string
(** Human-readable description of the result. *)
