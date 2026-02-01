(** Output rendering for atomyst.

    Pure functions that convert domain types to formatted strings.
*)

open Types

(** Count lines in a string (number of newlines) *)
let line_count s =
  String.fold_left (fun acc c -> if c = '\n' then acc + 1 else acc) 0 s

(** Convert definition_kind to display string *)
let kind_to_string = function
  | Class -> "class"
  | Function -> "function"
  | AsyncFunction -> "async function"
  | Variable -> "variable"
  | TypeAlias -> "type alias"

let plan_text plan =
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf "Found %d definitions in %s:\n"
      (List.length plan.definitions) plan.source_name);

  List.iter (fun defn ->
    Buffer.add_string buf
      (Printf.sprintf "  %-15s %-40s lines %d-%d\n"
        (kind_to_string defn.kind)
        defn.name
        defn.start_line
        defn.end_line)
  ) plan.definitions;

  Buffer.add_string buf
    (Printf.sprintf "\nWill create %d files:\n" (List.length plan.output_files));

  List.iter (fun f ->
    Buffer.add_string buf
      (Printf.sprintf "  %s (%d lines)\n" f.relative_path (line_count f.content))
  ) plan.output_files;

  (* Remove trailing newline to match Python *)
  let s = Buffer.contents buf in
  if String.length s > 0 && s.[String.length s - 1] = '\n' then
    String.sub s 0 (String.length s - 1)
  else s

let plan_json plan =
  let definitions =
    `List (List.map (fun d ->
      `Assoc [
        ("name", `String d.name);
        ("kind", `String (kind_to_string d.kind));
        ("start_line", `Int d.start_line);
        ("end_line", `Int d.end_line);
      ]
    ) plan.definitions)
  in
  let output_files =
    `List (List.map (fun f ->
      `Assoc [
        ("path", `String f.relative_path);
        ("lines", `Int (line_count f.content));
      ]
    ) plan.output_files)
  in
  let data = `Assoc [
    ("source", `String plan.source_name);
    ("definitions", definitions);
    ("output_files", output_files);
  ] in
  Yojson.Basic.pretty_to_string data

let extraction_text result ~name ~dry_run =
  let buf = Buffer.create 256 in

  if dry_run then begin
    Buffer.add_string buf
      (Printf.sprintf "[DRY RUN] Would extract '%s' to %s\n\n"
        name result.extracted.relative_path);
    Buffer.add_string buf "--- Extracted content ---\n";
    Buffer.add_string buf (String.trim result.extracted.content);
    Buffer.add_string buf "\n\n";
    Buffer.add_string buf "--- Remainder preview (first 20 lines) ---\n";

    let remainder_lines = String.split_on_char '\n' result.remainder in
    let preview_lines = List.filteri (fun i _ -> i < 20) remainder_lines in
    List.iter (fun line ->
      Buffer.add_string buf line;
      Buffer.add_string buf "\n"
    ) preview_lines;

    let total_lines = List.length remainder_lines in
    if total_lines > 20 then
      Buffer.add_string buf
        (Printf.sprintf "... (%d more lines)" (total_lines - 20))
  end else begin
    Buffer.add_string buf
      (Printf.sprintf "Extracted '%s' to %s" name result.extracted.relative_path)
  end;

  Buffer.contents buf

let extraction_json result ~name =
  let data = `Assoc [
    ("name", `String name);
    ("extracted", `Assoc [
      ("relative_path", `String result.extracted.relative_path);
      ("content", `String result.extracted.content);
    ]);
    ("remainder", `String result.remainder);
  ] in
  Yojson.Basic.pretty_to_string data

let error message =
  Printf.sprintf "Error: %s" message
