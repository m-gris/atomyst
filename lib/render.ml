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

(** Format line range: "line N" for single line, "lines N-M" for multi-line *)
let format_lines start_line end_line =
  if start_line = end_line then
    Printf.sprintf "line %d" start_line
  else
    Printf.sprintf "lines %d-%d" start_line end_line

(** Render definition list in file order *)
let list_text definitions ~source_name ~organized =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "Definitions in %s:\n\n" source_name);

  if organized then begin
    (* Group by kind *)
    let by_kind kind = List.filter (fun d -> d.kind = kind) definitions in
    let groups = [
      ("Classes", by_kind Class);
      ("Functions", by_kind Function);
      ("Async Functions", by_kind AsyncFunction);
      ("Type Aliases", by_kind TypeAlias);
      ("Variables", by_kind Variable);
    ] in
    List.iter (fun (label, defs) ->
      if defs <> [] then begin
        Buffer.add_string buf (Printf.sprintf "%s:\n" label);
        List.iter (fun d ->
          Buffer.add_string buf
            (Printf.sprintf "  %-20s %s\n" d.name (format_lines d.start_line d.end_line))
        ) defs;
        Buffer.add_string buf "\n"
      end
    ) groups
  end else begin
    (* File order *)
    List.iter (fun d ->
      Buffer.add_string buf
        (Printf.sprintf "  %-20s %-15s %s\n"
          d.name
          (kind_to_string d.kind)
          (format_lines d.start_line d.end_line))
    ) definitions;
    Buffer.add_string buf "\n"
  end;

  Buffer.add_string buf
    (Printf.sprintf "%d definitions found" (List.length definitions));
  Buffer.contents buf

(** Render definition list as JSON *)
let list_json definitions ~source_name =
  let defs =
    `List (List.map (fun d ->
      `Assoc [
        ("name", `String d.name);
        ("kind", `String (kind_to_string d.kind));
        ("start_line", `Int d.start_line);
        ("end_line", `Int d.end_line);
      ]
    ) definitions)
  in
  let data = `Assoc [
    ("source", `String source_name);
    ("definitions", defs);
    ("count", `Int (List.length definitions));
  ] in
  Yojson.Basic.pretty_to_string data

(** Get current date as ISO string *)
let current_date () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d"
    (tm.Unix.tm_year + 1900)
    (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday

(** Render manifest in YAML format *)
let manifest_yaml ~source_name ~prefix_kind ~definitions =
  let buf = Buffer.create 512 in
  Buffer.add_string buf "# Auto-generated by atomyst\n";
  Buffer.add_string buf (Printf.sprintf "source: %s\n" source_name);
  Buffer.add_string buf (Printf.sprintf "extracted: %s\n\n" (current_date ()));
  Buffer.add_string buf "definitions:\n";
  List.iter (fun (d : definition) ->
    let filename = Prefix.generate_filename ~prefix_kind d in
    Buffer.add_string buf (Printf.sprintf "  - file: %s\n" filename);
    Buffer.add_string buf (Printf.sprintf "    name: %s\n" d.name);
    Buffer.add_string buf (Printf.sprintf "    kind: %s\n" (kind_to_string d.kind));
    Buffer.add_string buf (Printf.sprintf "    lines: %d-%d\n" d.start_line d.end_line);
    Buffer.add_string buf "\n"
  ) definitions;
  Buffer.contents buf

(** Render manifest in JSON format *)
let manifest_json ~source_name ~prefix_kind ~definitions =
  let defs =
    `List (List.map (fun (d : definition) ->
      let filename = Prefix.generate_filename ~prefix_kind d in
      `Assoc [
        ("file", `String filename);
        ("name", `String d.name);
        ("kind", `String (kind_to_string d.kind));
        ("start_line", `Int d.start_line);
        ("end_line", `Int d.end_line);
      ]
    ) definitions)
  in
  let data = `Assoc [
    ("source", `String source_name);
    ("extracted", `String (current_date ()));
    ("definitions", defs);
  ] in
  Yojson.Basic.pretty_to_string data

(** Render manifest in Markdown format *)
let manifest_md ~source_name ~prefix_kind ~definitions =
  let buf = Buffer.create 512 in
  Buffer.add_string buf "# Atomyst Manifest\n\n";
  Buffer.add_string buf (Printf.sprintf "**Source:** `%s`\n\n" source_name);
  Buffer.add_string buf (Printf.sprintf "**Extracted:** %s\n\n" (current_date ()));
  Buffer.add_string buf "## Definitions\n\n";
  Buffer.add_string buf "| File | Name | Kind | Lines |\n";
  Buffer.add_string buf "|------|------|------|-------|\n";
  List.iter (fun (d : definition) ->
    let filename = Prefix.generate_filename ~prefix_kind d in
    Buffer.add_string buf
      (Printf.sprintf "| `%s` | %s | %s | %d-%d |\n"
        filename d.name (kind_to_string d.kind) d.start_line d.end_line)
  ) definitions;
  Buffer.contents buf

(** Render manifest in specified format *)
let manifest ~format ~source_name ~prefix_kind ~definitions =
  match format with
  | "json" -> (manifest_json ~source_name ~prefix_kind ~definitions, "MANIFEST.json")
  | "md" -> (manifest_md ~source_name ~prefix_kind ~definitions, "MANIFEST.md")
  | _ -> (manifest_yaml ~source_name ~prefix_kind ~definitions, "MANIFEST.yaml")
