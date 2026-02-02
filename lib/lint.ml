(** Lint atomized directories for prefix consistency.

    Verifies that filenames match their definition kinds.
    Pure analysis functions - I/O pushed to caller.
*)

open Types

type lint_issue = {
  file_path : string;
  expected_kinds : definition_kind list;
  actual_kind : definition_kind;
  definition_name : string;
  line : int;
}

type file_result =
  | Clean
  | Mismatch of lint_issue
  | NoDefinition
  | ParseError of string

type lint_result =
  | AllClean of int
  | Issues of lint_issue list
  | Error of string

let check_file ~dir ~filename ~source =
  (* Skip special files *)
  if Prefix.is_special_file filename then Clean
  else
    match Prefix.parse_filename filename with
    | None ->
      (* No prefix - unprefixed files are always clean *)
      Clean
    | Some parsed ->
      let expected_kinds = Prefix.prefix_to_kinds parsed.prefix in
      if expected_kinds = [] then Clean  (* Unknown prefix, ignore *)
      else
        let definitions = Extract.extract_definitions source in
        match definitions with
        | [] -> NoDefinition
        | defn :: _ ->
          if List.mem defn.kind expected_kinds then Clean
          else
            Mismatch {
              file_path = Filename.concat dir filename;
              expected_kinds;
              actual_kind = defn.kind;
              definition_name = defn.name;
              line = defn.start_line;
            }

let lint_directory ~dir ~read_file =
  (* Get list of .py files in directory *)
  match
    Sys.readdir dir
    |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".py")
    |> List.filter (fun f -> not (Prefix.is_special_file f))
  with
  | exception Sys_error msg -> Error msg
  | [] -> AllClean 0
  | files ->
    let results = List.filter_map (fun filename ->
      let path = Filename.concat dir filename in
      match read_file path with
      | None -> Some (ParseError (Printf.sprintf "Could not read %s" path))
      | Some source ->
        match check_file ~dir ~filename ~source with
        | Clean -> None
        | Mismatch issue -> Some (Mismatch issue)
        | NoDefinition -> None  (* Skip files with no definitions *)
        | ParseError msg -> Some (ParseError msg)
    ) files in
    let issues = List.filter_map (function
      | Mismatch issue -> Some issue
      | _ -> None
    ) results in
    if issues = [] then AllClean (List.length files)
    else Issues issues
