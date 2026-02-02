(** Filename prefix generation for --prefix-kind.

    Transforms definition kinds into filename prefixes and parses them back.
    Maintains separation between pure data (Types) and transformations (this module).
*)

open Types

type parsed_filename = {
  prefix : string;
  base_name : string;
}

let kind_to_prefix = function
  | Class -> "class"
  | Function -> "def"
  | AsyncFunction -> "async_def"
  | Variable -> "var"
  | TypeAlias -> "type"

let generate_filename ~prefix_kind (defn : definition) : string =
  let stem = Snake_case.to_snake_case defn.name in
  if prefix_kind then kind_to_prefix defn.kind ^ "_" ^ stem ^ ".py"
  else stem ^ ".py"

(** Regex: prefixed filename pattern
    Matches: class_*, def_*, async_def_*, var_*, type_*
    Note: async_def must come before def in alternation to match correctly *)
let re_prefixed = Re.Pcre.regexp {|^(async_def|class|def|var|type)_(.+)\.py$|}

let parse_filename filename : parsed_filename option =
  match Re.exec_opt re_prefixed filename with
  | None -> None
  | Some g -> Some { prefix = Re.Group.get g 1; base_name = Re.Group.get g 2 }

let prefix_to_kinds = function
  | "class" -> [Class]
  | "def" -> [Function]
  | "async_def" -> [AsyncFunction]
  | "var" -> [Variable]
  | "type" -> [TypeAlias]
  | _ -> []

let is_special_file filename =
  filename = "_constants.py" || filename = "__init__.py"
