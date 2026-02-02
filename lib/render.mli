(** Output rendering for atomyst.

    Pure functions that convert domain types to formatted strings.
    Separates data transformation from I/O.
*)

open Types

val kind_to_string : definition_kind -> string
(** [kind_to_string kind] converts a definition kind to display string.
    Class -> "class", Function -> "function", etc. *)

val plan_text : atomize_plan -> string
(** [plan_text plan] renders the atomization plan as human-readable text.
    Shows definitions found and files that will be created. *)

val plan_json : atomize_plan -> string
(** [plan_json plan] renders the atomization plan as JSON. *)

val extraction_text : extraction_result -> name:string -> dry_run:bool -> string
(** [extraction_text result ~name ~dry_run] renders an extraction result
    as human-readable text. Shows what was extracted and remainder preview. *)

val extraction_json : extraction_result -> name:string -> string
(** [extraction_json result ~name] renders an extraction result as JSON. *)

val error : string -> string
(** [error message] formats an error message. *)

val list_text : Types.definition list -> source_name:string -> organized:bool -> string
(** [list_text definitions ~source_name ~organized] renders a definition list
    as human-readable text. If [organized] is true, groups by kind. *)

val list_json : Types.definition list -> source_name:string -> string
(** [list_json definitions ~source_name] renders a definition list as JSON. *)

val manifest : format:string -> source_name:string -> prefix_kind:bool -> definitions:Types.definition list -> string * string
(** [manifest ~format ~source_name ~prefix_kind ~definitions] renders a manifest file
    preserving the original definition order. Returns (content, filename).
    Format can be "yaml", "json", or "md".
    When [prefix_kind] is true, filenames include kind prefix (e.g., class_user.py). *)
