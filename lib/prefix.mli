(** Filename prefix generation for --prefix-kind.

    Transforms definition kinds into filename prefixes and parses them back.
    Maintains separation between pure data (Types) and transformations (this module).
*)

open Types

(** Parsed components from a prefixed filename *)
type parsed_filename = {
  prefix : string;      (** "class", "def", "async_def", "var", "type" *)
  base_name : string;   (** snake_case name without prefix *)
}

val kind_to_prefix : definition_kind -> string
(** Map definition kind to filename prefix.
    - Class -> "class"
    - Function -> "def"
    - AsyncFunction -> "async_def"
    - Variable -> "var"
    - TypeAlias -> "type" *)

val generate_filename : prefix_kind:bool -> definition -> string
(** Generate filename for a definition.
    - prefix_kind=false: "user.py"
    - prefix_kind=true:  "class_user.py" *)

val parse_filename : string -> parsed_filename option
(** Parse prefix from filename. None if no recognized prefix.
    - "class_user.py" -> Some {prefix="class"; base_name="user"}
    - "async_def_fetch.py" -> Some {prefix="async_def"; base_name="fetch"}
    - "user.py" -> None *)

val prefix_to_kinds : string -> definition_kind list
(** Map prefix back to expected definition kinds.
    - "class" -> [Class]
    - "def" -> [Function]
    - "async_def" -> [AsyncFunction]
    - "var" -> [Variable]
    - "type" -> [TypeAlias]
    - unknown -> [] *)

val is_special_file : string -> bool
(** Check if filename should be skipped in lint.
    Returns true for "_constants.py" and "__init__.py". *)
