(** Core types for atomyst.

    Following FP principles: immutable data, no behavior.
    These are the "nouns" of the domain.
*)

(** Kind of top-level definition *)
type definition_kind =
  | Class
  | Function
  | AsyncFunction
  | Variable
  | TypeAlias
[@@deriving show, eq]

(** A top-level definition extracted from source *)
type definition = {
  name : string;
  kind : definition_kind;
  start_line : int;  (** 1-indexed, inclusive *)
  end_line : int;    (** 1-indexed, inclusive *)
}
[@@deriving show, eq]

(** An output file to be written *)
type output_file = {
  relative_path : string;
  content : string;
}
[@@deriving show, eq]

(** Result of extracting a single definition *)
type extraction_result = {
  extracted : output_file;
  remainder : string;
}
[@@deriving show, eq]

(** Plan for atomizing a file *)
type atomize_plan = {
  source_name : string;
  definitions : definition list;
  output_files : output_file list;
}
[@@deriving show, eq]
